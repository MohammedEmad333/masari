import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'calendar_repository.dart';
import 'notification_service.dart';

const _backgroundTaskName = 'moodle-calendar-sync';
const _backgroundUniqueName = 'moodle-calendar-periodic-sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _backgroundTaskName) return true;

    try {
      final repository = CalendarRepository();
      await repository.migrateLegacyStorage();
      if (await repository.loadCalendarUrl() == null) return true;

      final deadlines = await repository.sync();
      final offsets = await repository.loadReminderOffsets();
      final completed = await repository.loadCompletedIds();
      final perTask = await repository.loadTaskReminderOffsets();
      await NotificationService.init(requestPermissions: false);
      await NotificationService.scheduleAll(
        deadlines,
        reminderOffsetsHours: offsets,
        completedIds: completed,
        taskReminderOffsets: perTask,
      );
      return true;
    } catch (_) {
      // The next periodic run will retry. Avoid an aggressive retry loop for
      // invalid or expired Moodle calendar tokens.
      return true;
    }
  });
}

class BackgroundSyncService {
  BackgroundSyncService._();

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _backgroundUniqueName,
      _backgroundTaskName,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }
}
