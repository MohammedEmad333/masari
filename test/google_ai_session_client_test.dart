import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/ai_assistant_client.dart';
import 'package:moodle_reminder/services/google_ai_session_client.dart';

void main() {
  test('Google exchange requires a secure expected endpoint', () async {
    var calls = 0;
    final client = GoogleAiSessionClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      endpoint: Uri.parse('http://ai.example.org/v1/assistant/google-session'),
      idTokenProvider: () async => 'firebase',
      appCheckProvider: () async => 'appcheck',
    );
    await expectLater(
      client.exchange(),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'not_configured',
        ),
      ),
    );
    expect(calls, 0);
    client.dispose();
  });

  test('Google exchange sends ID token and App Check without body', () async {
    http.Request? captured;
    final client = GoogleAiSessionClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 401);
      }),
      endpoint: Uri.parse('https://ai.example.org/v1/assistant/google-session'),
      idTokenProvider: () async => 'firebase-id-token',
      appCheckProvider: () async => 'appcheck-token',
    );
    await expectLater(
      client.exchange(),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.code,
          'code',
          'sign_in_required',
        ),
      ),
    );
    expect(captured!.headers['authorization'], 'Bearer firebase-id-token');
    expect(captured!.headers['x-firebase-appcheck'], 'appcheck-token');
    expect(captured!.body, isEmpty);
    client.dispose();
  });
}
