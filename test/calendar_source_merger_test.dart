import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_source_merger.dart';

void main() {
  final due = DateTime.utc(2030, 5, 1);
  final task = Deadline(uid: 'same-id', title: 'Assignment', due: due);

  test('same Moodle UID in different feeds stays distinct', () {
    final merged = CalendarSourceMerger.merge({
      '': [task],
      'course-two': [task],
    });
    expect(merged, hasLength(2));
    expect(merged.map((item) => item.stableKey).toSet(), hasLength(2));
    expect(merged.first.uid, 'same-id');
  });

  test('repeated task within a source is deduplicated', () {
    final merged = CalendarSourceMerger.merge({
      '': [task, task],
    });
    expect(merged, hasLength(1));
  });

  test('additional sources preserve task details', () {
    final detailed = Deadline(
      uid: 'unique',
      title: 'Math',
      due: due,
      course: 'Calculus',
      priority: 3,
      url: 'https://moodle.example/task',
    );
    final merged = CalendarSourceMerger.merge({
      'course-two': [detailed],
    });
    expect(merged.single.course, 'Calculus');
    expect(merged.single.priority, 3);
    expect(merged.single.url, detailed.url);
  });
}
