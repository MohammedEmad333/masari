import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/moodle_task_link.dart';

Deadline task({String url = '', String description = ''}) => Deadline(
  uid: 'test',
  title: 'Study task',
  due: DateTime.utc(2030, 1, 1),
  url: url,
  description: description,
);

void main() {
  test('accepts a direct Moodle activity URL', () {
    final url = MoodleTaskLink.resolve(
      task(url: 'https://moodle.example.edu/mod/assign/view.php?id=123'),
    );
    expect(url?.path, '/mod/assign/view.php');
    expect(url?.queryParameters['id'], '123');
  });

  test('uses a safe description link if the URL field is empty', () {
    final url = MoodleTaskLink.resolve(
      task(
        description:
            'View assignment: https://moodle.example.edu/mod/quiz/view.php?id=45.',
      ),
    );
    expect(url?.queryParameters['id'], '45');
  });

  test('does not construct a link when no direct task URL is supplied', () {
    expect(MoodleTaskLink.resolve(task()), isNull);
  });

  test('rejects calendar credentials and token URLs', () {
    expect(
      MoodleTaskLink.resolve(
        task(
          url:
              'https://moodle.example.edu/calendar/export_execute.php?authtoken=secret',
        ),
      ),
      isNull,
    );
    expect(
      MoodleTaskLink.resolve(
        task(
          url:
              'https://moodle.example.edu/mod/assign/view.php?id=45&token=secret',
        ),
      ),
      isNull,
    );
  });

  test('rejects HTTP, user-info, missing activity ID and unrelated pages', () {
    for (final url in [
      'http://moodle.example.edu/mod/assign/view.php?id=1',
      'https://user:pass@moodle.example.edu/mod/assign/view.php?id=1',
      'https://moodle.example.edu/mod/assign/view.php?id=',
      'https://example.edu/news?id=1',
    ]) {
      expect(MoodleTaskLink.resolve(task(url: url)), isNull);
    }
  });
}
