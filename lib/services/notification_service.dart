import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../models/deadline.dart';
import 'reminder_notification_copy.dart';
import 'reminder_policy.dart';
import 'reminder_schedule_time.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static NotificationDetails _detailsFor({required bool arabic}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          'deadlines_v2',
          arabic ? 'تذكيرات المواعيد' : 'Deadline reminders',
          channelDescription: arabic
              ? 'تنبيهات المهام والواجبات والاختبارات القادمة في مساري'
              : 'Upcoming Masari task, assignment, quiz and exam reminders',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  // Android keeps notification channel labels separately from the app locale.
  // Re-registering the stable channel ID updates its user-visible name without
  // changing user-selected alert settings or scheduled notification IDs.
  static Future<void> _updateChannelLocale({required bool arabic}) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        'deadlines_v2',
        arabic ? 'تذكيرات المواعيد' : 'Deadline reminders',
        description: arabic
            ? 'تذكيرات المهام والواجبات والاختبارات القادمة في مساري'
            : 'Upcoming Masari task and assignment reminders',
        importance: Importance.high,
      ),
    );
  }

  static Future<void> init({bool requestPermissions = true}) async {
    if (!_initialized) {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('masari_notification'),
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
    // Do not re-request a permission Android has already granted.
    if (await android?.areNotificationsEnabled() != true) {
      await android?.requestNotificationsPermission();
    }
    // Exact alarms are optional. Do not request the special OS access while
    // initializing notifications: MIUI can reject that flow even when normal
    // notifications are enabled. scheduleAll uses an inexact fallback.
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<bool?> notificationsEnabled() async {
    await init(requestPermissions: false);
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
  }

  static Future<void> scheduleAll(
    List<Deadline> deadlines, {
    required List<int> reminderOffsetsHours,
    Set<String> completedIds = const {},
    Map<String, List<int>> taskReminderOffsets = const {},
    bool arabic = false,
  }) async {
    await init(requestPermissions: false);
    await _updateChannelLocale(arabic: arabic);

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    var canScheduleExact = false;
    try {
      canScheduleExact =
          await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      // OEM-specific failures must not block inexact reminder scheduling.
    }
    final scheduleMode = canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = DateTime.now();
    final pending = <_ScheduledReminder>[];
    for (final deadline in deadlines) {
      if (deadline.isPast || completedIds.contains(deadline.stableKey)) {
        continue;
      }
      // Manual tasks may specify a short reminder (5/15/30 minutes);
      // existing Moodle and older manual tasks keep global hour offsets.
      final minutesBefore = deadline.reminderMinutesBefore;
      if (minutesBefore == -1) continue;
      if (minutesBefore != null) {
        final fireAt = deadline.due.subtract(Duration(minutes: minutesBefore));
        if (minutesBefore > 0 && fireAt.isAfter(now)) {
          pending.add(
            _ScheduledReminder(
              id: _stableId('${deadline.stableKey}|before-min|$minutesBefore'),
              title: ReminderNotificationCopy.upcomingTitle(
                deadline,
                arabic: arabic,
              ),
              body: ReminderNotificationCopy.body(
                deadline,
                ReminderNotificationCopy.offsetMinutes(
                  minutesBefore,
                  arabic: arabic,
                ),
                arabic: arabic,
              ),
              when: fireAt,
              payload: deadline.stableKey,
            ),
          );
        }
      } else {
        for (final hours in offsetsForDeadline(
          deadline,
          reminderOffsetsHours,
          taskReminderOffsets,
        )) {
          final fireAt = deadline.due.subtract(Duration(hours: hours));
          if (!fireAt.isAfter(now)) continue;
          pending.add(
            _ScheduledReminder(
              id: _stableId('${deadline.stableKey}|before|$hours'),
              title: 'Due soon: ${deadline.title}',
              body: ReminderNotificationCopy.body(
                deadline,
                ReminderNotificationCopy.offsetHours(hours, arabic: arabic),
                arabic: arabic,
              ),
              when: fireAt,
              payload: deadline.stableKey,
            ),
          );
        }
      }
      if (deadline.due.isAfter(now)) {
        pending.add(
          _ScheduledReminder(
            id: _stableId('${deadline.stableKey}|due'),
            title: ReminderNotificationCopy.dueTitle(deadline, arabic: arabic),
            body: ReminderNotificationCopy.body(
              deadline,
              ReminderNotificationCopy.dueNow(arabic: arabic),
              arabic: arabic,
            ),
            when: deadline.due,
            payload: deadline.stableKey,
          ),
        );
      }
    }

    // Schedule upcoming notifications first; Android has a finite pending
    // notification capacity and an overflowing list should not erase the
    // soonest alerts.
    pending.sort((a, b) => a.when.compareTo(b.when));
    await _plugin.cancelAll();
    for (final reminder in pending.take(400)) {
      await _scheduleOne(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        when: reminder.when,
        payload: reminder.payload,
        scheduleMode: scheduleMode,
        arabic: arabic,
      );
    }
  }

  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    required AndroidScheduleMode scheduleMode,
    required bool arabic,
  }) async {
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: reminderScheduledInstant(when),
      notificationDetails: _detailsFor(arabic: arabic),
      payload: payload,
      androidScheduleMode: mode,
    );
    try {
      await schedule(scheduleMode);
    } on PlatformException {
      if (scheduleMode == AndroidScheduleMode.inexactAllowWhileIdle) rethrow;
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
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

  static Future<void> showTest({bool arabic = false}) async {
    await init(requestPermissions: true);
    await _updateChannelLocale(arabic: arabic);
    if (await notificationsEnabled() == false) {
      throw StateError('Android notifications are disabled');
    }
    await _plugin.show(
      id: 2147483000,
      title: ReminderNotificationCopy.getTestTitle(arabic: arabic),
      body: ReminderNotificationCopy.getTestBody(arabic: arabic),
      notificationDetails: _details,
    );
  }
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String payload;
}
