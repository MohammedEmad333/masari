import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/deadline_filters.dart';
import 'package:moodle_reminder/services/reminder_policy.dart';

void main() {
  final now = DateTime.utc(2030, 1, 1);
  final math = Deadline(
    uid: 'a',
    title: 'Assignment',
    course: 'Math',
    due: now.add(const Duration(days: 2)),
  );
  final physics = Deadline(
    uid: 'b',
    title: 'Quiz',
    course: 'Physics',
    due: now.add(const Duration(days: 1)),
  );

  test('filters by course and case-insensitive search', () {
    expect(filterDeadlines([math, physics], query: 'QUIZ'), [physics]);
    expect(filterDeadlines([math, physics], course: 'Math'), [math]);
    expect(filterDeadlines([math, physics], query: 'math'), [math]);
    expect(
      filterDeadlines([math, physics], course: 'Physics', query: 'math'),
      isEmpty,
    );
  });

  test('overdue deadlines can be identified without wall clock coupling', () {
    final old = Deadline(uid: 'old', title: 'Old', due: now);
    expect(old.due.isBefore(now.add(const Duration(minutes: 1))), isTrue);
  });

  test('per-task offsets override defaults and deduplicate', () {
    final overrides = <String, List<int>>{
      'a': [6, 6, 1],
    };
    expect(offsetsForDeadline(math, [24], overrides), [6, 1]);
    expect(offsetsForDeadline(physics, [24], overrides), [24]);
    expect(offsetsForDeadline(math, [24], {'a': []}), isEmpty);
  });

  test('schedule skips elapsed offsets, retains due-now alert', () {
    final deadline = Deadline(
      uid: 'soon',
      title: 'Soon',
      due: now.add(const Duration(hours: 2)),
    );
    final times = upcomingReminderTimes(deadline, [24, 1], {}, now: now);
    expect(times, [
      now.add(const Duration(hours: 1)),
      now.add(const Duration(hours: 2)),
    ]);
  });

  test('no alerts are scheduled for expired deadline', () {
    final overdue = Deadline(uid: 'old', title: 'Old', due: now);
    expect(upcomingReminderTimes(overdue, [24], {}, now: now), isEmpty);
  });
}
