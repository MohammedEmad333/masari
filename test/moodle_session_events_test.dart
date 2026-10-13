import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/moodle_session_events.dart';

void main() {
  test('imports event metadata without credentials', () {
    final events = MoodleSessionEvents.parse(
      '[{"id":42,"name":"Assignment","timestart":1800000000,'
      '"course":"Math","url":"https://moodle.example.edu/mod/assign/view.php?id=1"}]',
      Uri.parse('https://moodle.example.edu/'),
    );
    expect(events, hasLength(1));
    expect(events.first.title, 'Assignment');
    expect(events.first.course, 'Math');
    expect(events.first.uid, 'moodle-session:42');
    expect(events.first.url, contains('moodle.example.edu'));
  });

  test('rejects links to unrelated sites and malformed events', () {
    final events = MoodleSessionEvents.parse(
      '[{"id":1,"name":"Test","timestart":1800000000,'
      '"url":"https://evil.example/secret"},'
      '{"id":2,"name":"Missing timestamp"}]',
      Uri.parse('https://moodle.example.edu/'),
    );
    expect(events, hasLength(1));
    expect(events.first.url, isEmpty);
  });

  test('rejects non-list payload', () {
    expect(
      () => MoodleSessionEvents.parse(
        '{"error":"unauthorized"}',
        Uri.parse('https://moodle.example.edu/'),
      ),
      throwsFormatException,
    );
  });
}
