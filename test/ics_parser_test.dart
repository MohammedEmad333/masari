import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/ics_parser.dart';

void main() {
  group('IcsParser', () {
    test('ignores cancelled events regardless of status casing', () {
      const raw = '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:cancelled
SUMMARY:Cancelled exam
DTSTART:20300115T215900Z
STATUS:cancelled
END:VEVENT
BEGIN:VEVENT
UID:active
SUMMARY:Active exam
DTSTART:20300115T215900Z
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR''';
      expect(IcsParser.parse(raw).map((e) => e.uid), ['active']);
    });

    test('newer cancellation supersedes older active revision', () {
      const raw = '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:assignment
SUMMARY:Old assignment
DTSTART:20300115T215900Z
SEQUENCE:1
STATUS:CONFIRMED
END:VEVENT
BEGIN:VEVENT
UID:assignment
SUMMARY:Cancelled assignment
DTSTART:20300115T215900Z
SEQUENCE:2
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR''';
      expect(IcsParser.parse(raw), isEmpty);
    });

    test('newer confirmed revision restores cancelled event', () {
      const raw = '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:assignment
SUMMARY:Old cancelled assignment
DTSTART:20300115T215900Z
SEQUENCE:1
STATUS:CANCELLED
END:VEVENT
BEGIN:VEVENT
UID:assignment
SUMMARY:Restored assignment
DTSTART:20300116T215900Z
SEQUENCE:2
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR''';
      expect(IcsParser.parse(raw).single.title, 'Restored assignment');
    });

    test('parses Moodle metadata and UTC dates', () {
      const raw = '''BEGIN:VCALENDAR\r
BEGIN:VEVENT\r
UID:assignment-42@example.edu\r
SUMMARY:Assignment 2 is due\r
DTSTART:20300115T215900Z\r
DESCRIPTION:Submit\\nPart A\\, Part B\r
CATEGORIES:Software Engineering\r
URL:https://moodle.example.edu/mod/assign/view.php?id=42\r
LOCATION:Online\r
SEQUENCE:3\r
LAST-MODIFIED:20300110T120000Z\r
STATUS:CONFIRMED\r
END:VEVENT\r
END:VCALENDAR''';

      final result = IcsParser.parse(raw);

      expect(result, hasLength(1));
      final deadline = result.single;
      expect(deadline.uid, 'assignment-42@example.edu');
      expect(deadline.title, 'Assignment 2 is due');
      expect(deadline.course, 'Software Engineering');
      expect(deadline.description, 'Submit\nPart A, Part B');
      expect(deadline.url, contains('id=42'));
      expect(deadline.location, 'Online');
      expect(deadline.sequence, 3);
      expect(deadline.status, 'CONFIRMED');
      expect(deadline.due.toUtc(), DateTime.utc(2030, 1, 15, 21, 59));
      expect(deadline.lastModified?.toUtc(), DateTime.utc(2030, 1, 10, 12));
    });

    test('normalizes Moodle numeric course suffixes', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:33592@moodle.alaqsa.edu.ps\nSUMMARY:واجب المحاضرة 1 و 2 مستحق\nDTSTART:20301020T200000Z\nCATEGORIES:تصميم منطق الحـاسوب_176\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);

      expect(result.single.course, 'تصميم منطق الحـاسوب');
    });

    test('deduplicates the same Moodle UID and keeps the newest sequence', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:assignment-42@example.edu\nSUMMARY:Old title\nDTSTART:20300115T200000Z\nSEQUENCE:1\nLAST-MODIFIED:20300101T100000Z\nEND:VEVENT\nBEGIN:VEVENT\nUID:assignment-42@example.edu\nSUMMARY:Updated title\nDTSTART:20300116T210000Z\nSEQUENCE:2\nLAST-MODIFIED:20300102T100000Z\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);

      expect(result, hasLength(1));
      expect(result.single.title, 'Updated title');
      expect(result.single.sequence, 2);
      expect(result.single.due.toUtc(), DateTime.utc(2030, 1, 16, 21));
    });

    test('uses LAST-MODIFIED when duplicate UID sequences are equal', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:assignment-99@example.edu\nSUMMARY:Earlier revision\nDTSTART:20300201T120000Z\nSEQUENCE:0\nLAST-MODIFIED:20300101T080000Z\nEND:VEVENT\nBEGIN:VEVENT\nUID:assignment-99@example.edu\nSUMMARY:Later revision\nDTSTART:20300202T120000Z\nSEQUENCE:0\nLAST-MODIFIED:20300103T080000Z\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);

      expect(result, hasLength(1));
      expect(result.single.title, 'Later revision');
      expect(result.single.lastModified?.toUtc(), DateTime.utc(2030, 1, 3, 8));
    });

    test('unfolds continuation lines', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nSUMMARY:A very long assignment\n title\nDTSTART:20310101T120000Z\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);
      expect(result.single.title, 'A very long assignmenttitle');
    });

    test('treats date-only events as end of day', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:y\nSUMMARY:Exam day\nDTSTART;VALUE=DATE:20320520\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);
      expect(result.single.due.hour, 23);
      expect(result.single.due.minute, 59);
    });

    test('skips malformed events instead of crashing the feed', () {
      const raw =
          '''BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Broken\nDTSTART:not-a-date\nEND:VEVENT\nBEGIN:VEVENT\nUID:valid\nSUMMARY:Valid\nDTSTART:20350101T120000Z\nEND:VEVENT\nEND:VCALENDAR''';

      final result = IcsParser.parse(raw);
      expect(result, hasLength(1));
      expect(result.single.uid, 'valid');
    });
  });
}
