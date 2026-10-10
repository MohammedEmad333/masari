import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/deadline.dart';
import 'ics_parser.dart';
import 'reminder_policy.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'deadlines_v2',
      'Deadline reminders',
      channelDescription: 'Upcoming Moodle assignment, quiz and exam reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init({bool requestPermissions = true}) async {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    }

    if (!requestPermissions) return;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> scheduleAll(
    List<Deadline> deadlines, {
    required List<int> reminderOffsetsHours,
    Set<String> completedIds = const {},
    Map<String, List<int>> taskReminderOffsets = const {},
  }) async {
    await init(requestPermissions: false);
    await _plugin.cancelAll();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canScheduleExact = await android?.canScheduleExactNotifications();
    final scheduleMode = canScheduleExact == false
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : AndroidScheduleMode.exactAllowWhileIdle;

    final now = DateTime.now();
    for (final deadline in deadlines) {
      if (deadline.isPast || completedIds.contains(deadline.stableKey)) {
        continue;
      }

      for (final hours in offsetsForDeadline(
        deadline,
        reminderOffsetsHours,
        taskReminderOffsets,
      )) {
        final fireAt = deadline.due.subtract(Duration(hours: hours));
        if (!fireAt.isAfter(now)) continue;

        await _scheduleOne(
          id: _stableId('${deadline.stableKey}|before|$hours'),
          title: 'Due soon: ${deadline.title}',
          body: _body(deadline, _offsetLabel(hours)),
          when: fireAt,
          payload: deadline.stableKey,
          scheduleMode: scheduleMode,
        );
      }

      if (deadline.due.isAfter(now)) {
        await _scheduleOne(
          id: _stableId('${deadline.stableKey}|due'),
          title: 'Deadline now: ${deadline.title}',
          body: _body(deadline, 'Due now'),
          when: deadline.due,
          payload: deadline.stableKey,
          scheduleMode: scheduleMode,
        );
      }
    }
  }

  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    required AndroidScheduleMode scheduleMode,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details,
      payload: payload,
      androidScheduleMode: scheduleMode,
    );
  }

  static String _body(Deadline deadline, String prefix) {
    final course = deadline.course.isEmpty ? '' : '${deadline.course} • ';
    return '$prefix • $course${formatDue(deadline.due)}';
  }

  static String _offsetLabel(int hours) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return '$days ${days == 1 ? 'day' : 'days'} remaining';
    }
    return '$hours ${hours == 1 ? 'hour' : 'hours'} remaining';
  }

  static int _stableId(String value) {
    // Deterministic 31-bit FNV-1a hash so the same Moodle UID maps to the
    // same Android notification ID across syncs and app restarts.
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> showTest() async {
    await init(requestPermissions: true);
    await _plugin.show(
      id: 2147483000,
      title: 'Notifications are ready ✅',
      body: 'Moodle Reminder can alert you before upcoming deadlines.',
      notificationDetails: _details,
    );
  }
}
