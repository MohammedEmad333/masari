import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/ai_assistant_client.dart';

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
      consent: true,
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

  test('refuses without explicit consent or valid login', () async {
    var networkCalls = 0;
    final mock = MockClient((request) async {
      networkCalls++;
      return http.Response('{}', 200);
    });
    final service = AiAssistantClient(
      client: mock,
      endpoint: endpoint,
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => 'app-check-test-token',
    );
    await expectLater(
      service.ask(message: 'Hello', language: 'en', consent: false),
      throwsA(isA<AiAssistantException>()),
    );
    await expectLater(
      service.ask(message: 'Hello', language: 'en', consent: true),
      throwsA(isA<AiAssistantException>()),
    );
    expect(networkCalls, 0);
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
        consent: true,
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
      insecure.ask(message: 'Test', language: 'en', consent: true),
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
      service.ask(message: 'Test', language: 'ar', consent: true),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'quota_exceeded',
        ),
      ),
    );
  });
}
