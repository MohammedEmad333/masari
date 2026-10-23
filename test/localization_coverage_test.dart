import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';
import 'package:moodle_reminder/services/sync_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('switching app language saves selection and updates pending reminders', () async {
    final repository = CalendarRepository();
    var schedulingCalls = 0;
    final controller = AppController(
      repository,
      reminderScheduler: () async {
        schedulingCalls++;
      },
    );
    controller.manualDeadlines = [
      Deadline(
        uid: 'manual-1',
        title: 'واجب جامعي',
        due: DateTime(2030, 10, 23, 20),
      ),
    ];

    await controller.setLocale(const Locale('ar'));
    expect(controller.locale.languageCode, 'ar');
    expect(await repository.loadLocale(), 'ar');
    expect(schedulingCalls, 1);

    await controller.setLocale(const Locale('en'));
    expect(controller.locale.languageCode, 'en');
    expect(await repository.loadLocale(), 'en');
    expect(schedulingCalls, 2);
    controller.dispose();
  });

  test('sync troubleshooting stays Arabic for known Moodle errors', () {
    expect(
      SyncFeedback.errorMessage(
        'Moodle returned HTTP 403. Check the calendar URL.',
        arabic: true,
      ),
      contains('HTTP 403'),
    );
    expect(
      SyncFeedback.errorMessage(
        'Moodle calendar download timed out. Please retry.',
        arabic: true,
      ),
      contains('انتهت مهلة'),
    );
    expect(
      SyncFeedback.errorMessage(
        'Could not reach the Moodle server. Check connectivity or DNS.',
        arabic: true,
      ),
      contains('تعذّر الوصول'),
    );
    expect(
      SyncFeedback.errorMessage(
        'Enter a valid Moodle calendar URL.',
        arabic: true,
      ),
      contains('أدخل'),
    );
    expect(
      SyncFeedback.errorMessage('Unrecognized network issue', arabic: true),
      isNot(contains('Unrecognized')),
    );
  });

  test('outdated user-facing product name is absent from key app screens', () {
    final service =
        File('lib/services/notification_service.dart').readAsStringSync();
    final localCourses =
        File('lib/screens/local_courses_screen.dart').readAsStringSync();
    expect(service, isNot(contains('Moodle Reminder can alert')));
    expect(localCourses, isNot(contains('using Moodle Reminder')));
    expect(service, contains('ReminderNotificationCopy.getTestBody'));
  });

  test('background syncing and widgets receive the selected app language', () {
    final background =
        File('lib/services/background_sync_service.dart').readAsStringSync();
    final bridge = File('lib/services/home_widget_bridge.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/com/example/moodle_reminder/MoodleWidgetProvider.kt',
    ).readAsStringSync();

    expect(background, contains("loadLocale() == 'ar'"));
    expect(bridge, contains("'language': languageCode == 'ar'"));
    expect(native, contains('createConfigurationContext'));
    expect(native, contains('language'));
  });
}
