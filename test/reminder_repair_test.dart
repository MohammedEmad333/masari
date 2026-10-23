import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  test('enabled notifications can fail during scheduling', () async {
    final controller = AppController(
      CalendarRepository(),
      notificationInitializer: () async {},
      notificationPermissionChecker: () async => true,
      reminderScheduler: () async {
        throw StateError('scheduling failed');
      },
    );

    expect(await controller.repairReminders(), isFalse);
    expect(
      controller.reminderRepairFailure,
      ReminderRepairFailure.schedulingFailed,
    );
    expect(controller.reminderSchedulingFailed, isTrue);
    controller.dispose();
  });

  test('disabled permissions are reported separately', () async {
    var scheduled = false;
    final controller = AppController(
      CalendarRepository(),
      notificationInitializer: () async {},
      notificationPermissionChecker: () async => false,
      reminderScheduler: () async {
        scheduled = true;
      },
    );

    expect(await controller.repairReminders(), isFalse);
    expect(
      controller.reminderRepairFailure,
      ReminderRepairFailure.permissionDenied,
    );
    expect(scheduled, isFalse);
    controller.dispose();
  });

  test('initialization failure is not blamed on permission', () async {
    final controller = AppController(
      CalendarRepository(),
      notificationInitializer: () async {
        throw StateError('timezone unavailable');
      },
      notificationPermissionChecker: () async => true,
      reminderScheduler: () async {},
    );

    expect(await controller.repairReminders(), isFalse);
    expect(
      controller.reminderRepairFailure,
      ReminderRepairFailure.initializationFailed,
    );
    controller.dispose();
  });

  test('successful repair clears previous reminder failure', () async {
    final controller = AppController(
      CalendarRepository(),
      notificationInitializer: () async {},
      notificationPermissionChecker: () async => true,
      reminderScheduler: () async {},
    );
    controller.reminderSchedulingFailed = true;

    expect(await controller.repairReminders(), isTrue);
    expect(controller.reminderRepairFailure, isNull);
    expect(controller.reminderSchedulingFailed, isFalse);
    controller.dispose();
  });
}
