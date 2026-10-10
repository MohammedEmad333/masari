import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'cached overdue and upcoming assignments survive offline loading',
    () async {
      final now = DateTime.now();
      final past = Deadline(
        uid: 'past',
        title: 'Late assignment',
        due: now.subtract(const Duration(days: 1)),
      );
      final future = Deadline(
        uid: 'future',
        title: 'Upcoming quiz',
        due: now.add(const Duration(days: 1)),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'deadline_cache_v2',
        jsonEncode([future.toJson(), past.toJson()]),
      );

      final restored = await CalendarRepository().loadCachedDeadlines();
      expect(restored.map((d) => d.uid).toList(), ['past', 'future']);
    },
  );

  test(
    'per-task overrides are saved, restored and cleared on disconnect',
    () async {
      final repository = CalendarRepository();
      await repository.saveTaskReminderOffsets({
        'assignment-id': [24, 6],
        'no-early-alerts': [],
      });

      final restored = await repository.loadTaskReminderOffsets();
      expect(restored['assignment-id'], [24, 6]);
      expect(restored['no-early-alerts'], isEmpty);

      await repository.clearCachedCalendarData();
      expect(await repository.loadTaskReminderOffsets(), isEmpty);
    },
  );

  test('invalid persisted override data falls back to empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('task_reminder_offsets_v1', '{oops');
    expect(await CalendarRepository().loadTaskReminderOffsets(), isEmpty);
  });
}
