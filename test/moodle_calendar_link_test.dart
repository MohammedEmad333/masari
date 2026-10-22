import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/moodle_calendar_link.dart';

void main() {
  const server = 'https://university.example.edu/moodle/';

  test('export URL uses the same university Moodle base path', () {
    expect(
      MoodleCalendarLink.exportPage(server)?.toString(),
      'https://university.example.edu/moodle/calendar/export.php',
    );
  });

  test('only same-site HTTPS Moodle subscription URLs are accepted', () {
    const valid =
        'https://university.example.edu/moodle/calendar/export_execute.php'
        '?preset_what=all&authtoken=privateToken';
    expect(MoodleCalendarLink.fromBrowser(valid, server), valid);

    expect(
      MoodleCalendarLink.fromBrowser(
        'https://evil.example/moodle/calendar/export_execute.php'
        '?authtoken=stolen',
        server,
      ),
      isNull,
    );
    expect(
      MoodleCalendarLink.fromBrowser(
        'http://university.example.edu/moodle/calendar/export_execute.php'
        '?authtoken=privateToken',
        server,
      ),
      isNull,
    );
    expect(
      MoodleCalendarLink.fromBrowser(
        'https://university.example.edu/moodle/calendar/export_execute.php'
        '?preset_what=all',
        server,
      ),
      isNull,
    );
  });

  test('rejects site-specific paths and URL fragments', () {
    expect(
      MoodleCalendarLink.fromBrowser(
        'https://university.example.edu/moodle/login/index.php'
        '?authtoken=foo',
        server,
      ),
      isNull,
    );
    expect(
      MoodleCalendarLink.fromBrowser(
        'https://university.example.edu/moodle/calendar/export_execute.php'
        '?authtoken=foo#fragment',
        server,
      ),
      isNull,
    );
  });
}
