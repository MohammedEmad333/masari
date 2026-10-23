import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';
import 'package:moodle_reminder/services/reminder_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual reminders support five minutes or no alerts', () {
    final now = DateTime.utc(2030, 10, 23, 18);
    final due = now.add(const Duration(minutes: 15));
    final short = Deadline(
      uid: 'manual-short',
      title: 'Test',
      due: due,
      reminderMinutesBefore: 5,
    );
    final noAlerts = Deadline(
      uid: 'manual-none',
      title: 'Test',
      due: due,
      reminderMinutesBefore: -1,
    );
    expect(upcomingReminderTimes(short, [24, 6, 1], {}, now: now), [
      now.add(const Duration(minutes: 10)),
      due,
    ]);
    expect(upcomingReminderTimes(noAlerts, [1], {}, now: now), isEmpty);
  });

  test('existing task data remains backward compatible', () {
    final old = Deadline.fromJson({
      'uid': 'manual-old',
      'title': 'Existing task',
      'due': '2030-10-23T20:00:00.000',
    });
    expect(old.reminderMinutesBefore, isNull);
    final restored = Deadline.fromJson(
      Deadline(
        uid: 'manual-new',
        title: 'New task',
        due: DateTime.utc(2030, 10, 23, 20),
        reminderMinutesBefore: 15,
      ).toJson(),
    );
    expect(restored.reminderMinutesBefore, 15);
  });

  test('failed Android scheduling never duplicates a saved task', () async {
    final repository = CalendarRepository();
    final controller = AppController(
      repository,
      notificationInitializer: () async {},
      reminderScheduler: () async {
        throw StateError('Android scheduling failed');
      },
    );
    final uid = 'manual-one';
    final due = DateTime.utc(2030, 10, 23, 20);
    await controller.saveManualDeadline(
      Deadline(
        uid: uid,
        title: 'Initial title',
        due: due,
        reminderMinutesBefore: 5,
      ),
    );
    expect(controller.manualDeadlines.length, 1);
    expect(controller.reminderSchedulingFailed, isTrue);
    expect(
      (await repository.loadManualDeadlines()).single.title,
      'Initial title',
    );

    await controller.saveManualDeadline(
      Deadline(
        uid: uid,
        title: 'Updated title',
        due: due,
        reminderMinutesBefore: 15,
      ),
    );
    expect(controller.manualDeadlines.length, 1);
    expect(
      (await repository.loadManualDeadlines()).single.title,
      'Updated title',
    );
    expect(
      (await repository.loadManualDeadlines()).single.reminderMinutesBefore,
      15,
    );
    controller.dispose();
  });
}
