import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/ai_assistant_client.dart';
import 'package:moodle_reminder/services/oracle_ai_session_store.dart';

void main() {
  final endpoint = Uri.parse('https://ai.example.org/v1/assistant/ask');
  final token = 'msr_${List.filled(64, 'a').join()}';

  test(
    'sends only explicit question, language and consent with Oracle bearer',
    () async {
      http.Request? captured;
      final client = AiAssistantClient(
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"answer":"Try spaced repetition."}', 200);
        }),
        endpoint: endpoint,
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
      );
      final answer = await client.ask(
        message: 'How do I revise?',
        language: 'en',
      );
      expect(answer, 'Try spaced repetition.');
      expect(captured!.headers['authorization'], 'Bearer $token');
      expect(captured!.headers.containsKey('x-firebase-appcheck'), false);
      expect(jsonDecode(captured!.body), {
        'message': 'How do I revise?',
        'language': 'en',
        'consent': true,
      });
      client.dispose();
    },
  );

  test('requires a valid Oracle session before sending', () async {
    var requests = 0;
    final client = AiAssistantClient(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
      endpoint: endpoint,
      oracleSessionProvider: () async => null,
    );
    await expectLater(
      client.ask(message: 'Hello', language: 'en'),
      throwsA(
        isA<AiAssistantException>().having(
          (e) => e.code,
          'code',
          'sign_in_required',
        ),
      ),
    );
    expect(requests, 0);
    client.dispose();
  });

  test(
    'rejects credential-bearing prompts and insecure endpoints before HTTP',
    () async {
      var requests = 0;
      final mock = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final secure = AiAssistantClient(
        client: mock,
        endpoint: endpoint,
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
      );
      await expectLater(
        secure.ask(
          message: 'https://moodle.example/calendar?authtoken=secret',
          language: 'en',
        ),
        throwsA(
          isA<AiAssistantException>().having(
            (e) => e.code,
            'code',
            'sensitive_content',
          ),
        ),
      );
      final insecure = AiAssistantClient(
        client: mock,
        endpoint: Uri.parse('http://ai.example.org/v1/assistant/ask'),
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
      );
      await expectLater(
        insecure.ask(message: 'Test', language: 'en'),
        throwsA(isA<AiAssistantException>()),
      );
      expect(requests, 0);
      secure.dispose();
      insecure.dispose();
    },
  );

  test(
    'maps revoked Oracle sessions and quota errors to typed exceptions',
    () async {
      final expired = AiAssistantClient(
        client: MockClient((_) async => http.Response('{}', 401)),
        endpoint: endpoint,
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 10)),
        ),
      );
      await expectLater(
        expired.ask(message: 'Test', language: 'ar'),
        throwsA(
          isA<AiAssistantException>().having(
            (e) => e.code,
            'code',
            'oracle_session_expired',
          ),
        ),
      );
      final limited = AiAssistantClient(
        client: MockClient((_) async => http.Response('{}', 429)),
        endpoint: endpoint,
        oracleSessionProvider: () async => OracleAiSession(
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 10)),
        ),
      );
      await expectLater(
        limited.ask(message: 'Test', language: 'ar'),
        throwsA(
          isA<AiAssistantException>().having(
            (e) => e.code,
            'code',
            'quota_exceeded',
          ),
        ),
      );
      expired.dispose();
      limited.dispose();
    },
  );
}
