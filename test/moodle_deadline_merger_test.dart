import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/moodle_deadline_merger.dart';

void main() {
  final due = DateTime.utc(2030, 1, 1);
  test('prefers calendar version of duplicated API assignment', () {
    final calendar = Deadline(
      uid: 'ical-1',
      title: 'Exam',
      course: 'Science',
      due: due,
    );
    final duplicate = Deadline(
      uid: 'api-1',
      title: ' Exam ',
      course: 'SCIENCE',
      due: due,
    );
    final distinct = Deadline(
      uid: 'api-2',
      title: 'Essay',
      course: 'Science',
      due: due,
    );
    final merged = MoodleDeadlineMerger.merge([
      calendar,
    ], [duplicate, distinct]);
    expect(merged, hasLength(2));
    expect(merged.first.uid, 'ical-1');
    expect(merged.last.uid, 'api-2');
  });
}
