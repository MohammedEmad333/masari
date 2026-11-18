import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/ai_assistant_client.dart';
import 'package:moodle_reminder/services/oracle_ai_session_store.dart';

void main() {
  final endpoint = Uri.parse('https://ai.example.org/v1/assistant/ask');

  test('never sends deadlines or Moodle tokens', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response('{"answer":"Try spaced repetition."}', 200);
    });
    final service = AiAssistantClient(
      client: mock,
      endpoint: endpoint,
      tokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    final answer = await service.ask(
      message: 'How do I revise?',
      language: 'en',
    );
    expect(answer, 'Try spaced repetition.');
    expect(captured!.headers['authorization'], 'Bearer firebase-id-token');
    expect(captured!.headers['x-firebase-appcheck'], 'app-check-test-token');
    expect(jsonDecode(captured!.body), {
      'message': 'How do I revise?',
      'language': 'en',
      'consent': true,
    });
    service.dispose();
  });

  test('requires a valid login before sending a question', () async {
    var networkCalls = 0;
    final service = AiAssistantClient(
      client: MockClient((request) async {
        networkCalls++;
        return http.Response('{}', 200);
      }),
      endpoint: endpoint,
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    await expectLater(
      service.ask(message: 'Hello', language: 'en'),
      throwsA(isA<AiAssistantException>()),
    );
    expect(networkCalls, 0);
    service.dispose();
  });

  test('rejects secret URLs and insecure proxy schemes', () async {
    var requests = 0;
    final mock = MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    });
    final service = AiAssistantClient(
      client: mock,
      endpoint: endpoint,
      tokenProvider: () async => 'token',
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    await expectLater(
      service.ask(
        message: 'https://moodle.example/calendar?authtoken=secret',
        language: 'en',
      ),
      throwsA(isA<AiAssistantException>()),
    );
    final insecure = AiAssistantClient(
      client: mock,
      endpoint: Uri.parse('http://ai.example.org/v1/assistant/ask'),
      tokenProvider: () async => 'token',
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    await expectLater(
      insecure.ask(message: 'Test', language: 'en'),
      throwsA(isA<AiAssistantException>()),
    );
    expect(requests, 0);
  });

  test('maps quota HTTP errors to typed exception', () async {
    final service = AiAssistantClient(
      client: MockClient((_) async => http.Response('{}', 429)),
      endpoint: endpoint,
      tokenProvider: () async => 'token',
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    await expectLater(
      service.ask(message: 'Test', language: 'ar'),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'quota_exceeded',
        ),
      ),
    );
  });

  test(
    'Oracle session uses bearer without calling Firebase/App Check',
    () async {
      http.Request? captured;
      final token = 'msr_${List.filled(64, 'a').join()}';
      final client = AiAssistantClient(
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"answer":"Oracle works"}', 200);
        }),
        endpoint: endpoint,
        tokenProvider: () async => throw StateError('Do not access Firebase'),
        appCheckTokenProvider: () async =>
            throw StateError('Do not access App Check'),
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
      );
      final answer = await client.ask(message: 'Hello', language: 'en');
      expect(answer, 'Oracle works');
      expect(captured!.headers['authorization'], 'Bearer $token');
      expect(captured!.headers.containsKey('x-firebase-appcheck'), false);
    },
  );

  test(
    'revoked Oracle bearer does not silently fall back to Firebase',
    () async {
      var firebaseCalls = 0;
      final client = AiAssistantClient(
        client: MockClient((_) async => http.Response('{}', 401)),
        endpoint: endpoint,
        tokenProvider: () async {
          firebaseCalls++;
          return 'firebase';
        },
        oracleSessionProvider: () async => OracleAiSession(
          'msr_${List.filled(64, 'b').join()}',
          DateTime.now().toUtc().add(const Duration(minutes: 15)),
        ),
      );
      await expectLater(
        client.ask(message: 'Hello', language: 'en'),
        throwsA(
          isA<AiAssistantException>().having(
            (e) => e.code,
            'code',
            'oracle_session_expired',
          ),
        ),
      );
      expect(firebaseCalls, 0);
    },
  );

  test('missing App Check token blocks Firebase request before HTTP', () async {
    var calls = 0;
    final client = AiAssistantClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      endpoint: endpoint,
      tokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => null,
      oracleSessionProvider: () async => null,
    );
    await expectLater(
      client.ask(message: 'Help', language: 'en'),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'app_check_token_unavailable',
        ),
      ),
    );
    expect(calls, 0);
    client.dispose();
  });

  test('App Check retrieval failure never sends Firebase request', () async {
    var calls = 0;
    final client = AiAssistantClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      endpoint: endpoint,
      tokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => throw StateError('integrity failed'),
      oracleSessionProvider: () async => null,
    );
    await expectLater(
      client.ask(message: 'Help', language: 'en'),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'app_check_token_unavailable',
        ),
      ),
    );
    expect(calls, 0);
    client.dispose();
  });

  test('Firebase HTTP 403 is distinct from device token retrieval', () async {
    var calls = 0;
    final client = AiAssistantClient(
      client: MockClient((request) async {
        calls++;
        expect(request.headers['x-firebase-appcheck'], 'valid-app-check');
        return http.Response('{}', 403);
      }),
      endpoint: endpoint,
      tokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => 'valid-app-check',
      oracleSessionProvider: () async => null,
    );
    await expectLater(
      client.ask(message: 'Help', language: 'en'),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'app_check_failed',
        ),
      ),
    );
    expect(calls, 1);
    client.dispose();
  });

  test('Oracle HTTP 403 never blames Firebase App Check', () async {
    var calls = 0;
    final bearer = 'msr_${List.filled(64, 'c').join()}';
    final client = AiAssistantClient(
      client: MockClient((request) async {
        calls++;
        expect(request.headers['authorization'], 'Bearer $bearer');
        expect(request.headers.containsKey('x-firebase-appcheck'), false);
        return http.Response('{}', 403);
      }),
      endpoint: endpoint,
      tokenProvider: () async => throw StateError('Firebase must not run'),
      appCheckTokenProvider: () async =>
          throw StateError('App Check must not run'),
      oracleSessionProvider: () async => OracleAiSession(
        bearer,
        DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
    );
    await expectLater(
      client.ask(message: 'Help', language: 'en'),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'oracle_access_denied',
        ),
      ),
    );
    expect(calls, 1);
    client.dispose();
  });
}
