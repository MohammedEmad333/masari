import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/deadline_collection.dart';

void main() {
  final due = DateTime.utc(2030, 1, 10);

  Deadline task(
    String uid,
    String title, {
    String course = '',
    int priority = 1,
  }) => Deadline(
    uid: uid,
    title: title,
    course: course,
    due: due,
    priority: priority,
  );

  test('background reminder collection retains every non-calendar source', () {
    final calendar = task('ics-1', 'Quiz');
    final api = task('api-1', 'Project');
    final session = task('session-1', 'Seminar');
    final manual = task('manual-1', 'Study session', priority: 3);

    final all = DeadlineCollection.combine(
      calendar: [calendar],
      api: [api],
      session: [session],
      manual: [manual],
    );

    expect(all.map((item) => item.uid).toSet(), {
      'ics-1',
      'api-1',
      'session-1',
      'manual-1',
    });
    expect(all.first.uid, 'manual-1');
  });

  test('deduplicates matching Moodle API and iCalendar deadlines', () {
    final calendar = task('ics-1', 'Homework', course: 'Math');
    final apiDuplicate = task('api-1', 'Homework', course: 'Math');
    final manual = task('manual-1', 'Homework', course: 'Math');

    final all = DeadlineCollection.combine(
      calendar: [calendar],
      api: [apiDuplicate],
      session: [],
      manual: [manual],
    );

    expect(all.map((item) => item.uid), ['ics-1', 'manual-1']);
  });

  test('works when only offline sources have deadlines', () {
    final taskOnly = task('manual-1', 'Offline task');
    final result = DeadlineCollection.combine(
      calendar: [],
      api: [],
      session: [],
      manual: [taskOnly],
    );

    expect(result, [taskOnly]);
  });
}
