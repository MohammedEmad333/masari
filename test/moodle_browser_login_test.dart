import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/moodle_browser_login.dart';

void main() {
  test('uses university HTTPS login page without handling credentials', () {
    expect(
      MoodleBrowserLogin.universityLoginUrl(
        'https://uni.example/moodle',
      ).toString(),
      'https://uni.example/moodle/login/index.php',
    );
  });

  test('rejects unsafe or ambiguous server addresses', () {
    for (final input in [
      'http://uni.example/moodle',
      'https://student:secret@uni.example',
      'https://uni.example/moodle?token=secret',
      'https://uni.example/#password',
      'not a url',
    ]) {
      expect(MoodleBrowserLogin.universityLoginUrl(input), isNull);
    }
  });
}
