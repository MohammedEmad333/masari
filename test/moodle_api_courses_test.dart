import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/moodle_api_client.dart';

void main() {
  test('loads enrolled courses and maps Moodle assignments to deadlines', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.bodyFields['wsfunction'] ?? '');
      expect(request.method, 'POST');
      expect(request.url.path, '/moodle/webservice/rest/server.php');
      if (requests.last == 'core_enrol_get_users_courses') {
        expect(request.bodyFields['userid'], '7');
        return http.Response(jsonEncode([{'id': 4, 'fullname': 'Science'}]), 200);
      }
      expect(request.bodyFields['courseids[0]'], '4');
      return http.Response(jsonEncode({'courses': [
        {'id': 4, 'fullname': 'Science', 'assignments': [
          {'id': 9, 'cmid': 12, 'name': 'Exam', 'duedate': 1893456000},
          {'id': 10, 'name': 'Without deadline', 'duedate': 0},
        ]},
      ]}), 200);
    });
    final api = MoodleApiClient(
      baseUrl: Uri.parse('https://moodle.example/moodle/'),
      token: 'private',
      client: client,
    );
    final courses = await api.courses(7);
    expect(courses.single['fullname'], 'Science');
    final deadlines = await api.assignments([4]);
    expect(deadlines, hasLength(1));
    expect(deadlines.single.uid, 'moodle-api:4:9');
    expect(deadlines.single.course, 'Science');
    expect(deadlines.single.due.year, 2030);
    expect(requests, ['core_enrol_get_users_courses', 'mod_assign_get_assignments']);
    api.close();
  });

  test('API failures do not expose access token in exception', () async {
    final api = MoodleApiClient(
      baseUrl: Uri.parse('https://moodle.example/'),
      token: 'sensitive-value',
      client: MockClient((request) async => http.Response(
        jsonEncode({'exception': 'moodle_exception', 'errorcode': 'accessdenied'}),
        200,
      )),
    );
    await expectLater(api.assignments([1]), throwsA(isA<MoodleApiException>()));
    api.close();
  });
}
