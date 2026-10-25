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


  test('normalizes any Moodle export period to custom', () {
    for (final period in ['monthnow', 'weeknext', 'monthnext', 'anything']) {
      final original =
          'https://moodle.example.edu/calendar/export_execute.php'
          '?userid=42&authtoken=secret&preset_what=all&preset_time=$period';
      final updated = MoodleCalendarLink.preferCustomPeriod(original);
      final uri = Uri.parse(updated);
      expect(uri.queryParameters['preset_time'], 'custom');
      expect(uri.queryParameters['authtoken'], 'secret');
      expect(uri.queryParameters['userid'], '42');
      expect(uri.queryParameters['preset_what'], 'all');
    }
  });

  test('adds missing period and leaves existing custom unchanged', () {
    const original =
        'https://moodle.example.edu/calendar/export_execute.php'
        '?userid=42&authtoken=secret';
    final updated = MoodleCalendarLink.preferCustomPeriod(original);
    expect(Uri.parse(updated).queryParameters['preset_time'], 'custom');
    expect(MoodleCalendarLink.preferCustomPeriod(updated), updated);
  });

  test('does not rewrite unrelated or unauthenticated calendar URLs', () {
    const ics = 'https://example.edu/feed.ics?preset_time=monthnow';
    const withoutToken =
        'https://moodle.example.edu/calendar/export_execute.php'
        '?preset_time=monthnow';
    expect(MoodleCalendarLink.preferCustomPeriod(ics), ics);
    expect(MoodleCalendarLink.preferCustomPeriod(withoutToken), withoutToken);
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
