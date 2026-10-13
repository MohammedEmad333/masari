import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodle_reminder/services/moodle_compatibility_checker.dart';

void main() {
  test(
    'detects responding endpoints without making credential claims',
    () async {
      final urls = <String>[];
      final checker = MoodleCompatibilityChecker(
        client: MockClient((request) async {
          urls.add(request.url.path);
          return http.Response('not authenticated', 403);
        }),
      );
      final result = await checker.check('https://example.edu/moodle/');
      expect(result.loginReachable, isTrue);
      expect(result.apiEndpointReachable, isTrue);
      expect(urls, [
        '/moodle/login/index.php',
        '/moodle/webservice/rest/server.php',
      ]);
      checker.close();
    },
  );

  test('treats unavailable endpoints as unverified', () async {
    final checker = MoodleCompatibilityChecker(
      client: MockClient((request) async => http.Response('', 404)),
    );
    final result = await checker.check('https://example.edu/moodle/');
    expect(result.loginReachable, isFalse);
    expect(result.apiEndpointReachable, isFalse);
    checker.close();
  });

  test('does not allow insecure university URLs', () async {
    final checker = MoodleCompatibilityChecker(
      client: MockClient((request) async => http.Response('', 200)),
    );
    await expectLater(
      checker.check('http://example.edu'),
      throwsFormatException,
    );
    checker.close();
  });
}
