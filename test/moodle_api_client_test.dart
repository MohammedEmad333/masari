import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/moodle_api_client.dart';

void main() {
  test('requires HTTPS and a nonempty API token', () {
    expect(
      () => MoodleApiClient(baseUrl: Uri.parse('http://moodle.example/'), token: 'x'),
      throwsArgumentError,
    );
    expect(
      () => MoodleApiClient(baseUrl: Uri.parse('https://moodle.example/'), token: ''),
      throwsArgumentError,
    );
  });

  test('fetches site info using POST and checks Moodle errors', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/webservice/rest/server.php');
      expect(request.bodyFields['wsfunction'], 'core_webservice_get_site_info');
      expect(request.bodyFields['wstoken'], 'secret');
      expect(request.url.queryParameters.containsKey('wstoken'), isFalse);
      return http.Response(jsonEncode({'sitename': 'University Moodle'}), 200);
    });
    final api = MoodleApiClient(
      baseUrl: Uri.parse('https://moodle.example/'),
      token: 'secret',
      client: client,
    );
    expect((await api.siteInfo())['sitename'], 'University Moodle');
    api.close();
  });

  test('reports Moodle credential failures without exposing tokens', () async {
    final client = MockClient((request) async => http.Response(
      jsonEncode({'exception': 'moodle_exception', 'errorcode': 'invalidtoken'}),
      200,
    ));
    final api = MoodleApiClient(
      baseUrl: Uri.parse('https://moodle.example/'),
      token: 'private-token',
      client: client,
    );
    await expectLater(api.siteInfo(), throwsA(isA<MoodleApiException>()));
    api.close();
  });
}
