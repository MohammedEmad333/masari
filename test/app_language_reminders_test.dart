import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('switching languages saves preference and refreshes future alerts', () async {
    final repository = CalendarRepository();
    var schedules = 0;
    final controller = AppController(
      repository,
      reminderScheduler: () async {
        schedules++;
      },
    );
    controller.manualDeadlines = [
      Deadline(
        uid: 'one',
        title: 'تجربة الإشعارات',
        due: DateTime.now().add(const Duration(hours: 2)),
      ),
    ];

    await controller.setLocale(const Locale('ar'));
    expect(controller.locale.languageCode, 'ar');
    expect(await repository.loadLocale(), 'ar');
    expect(schedules, 1);

    await controller.setLocale(const Locale('en'));
    expect(controller.locale.languageCode, 'en');
    expect(await repository.loadLocale(), 'en');
    expect(schedules, 2);

    controller.dispose();
  });
}
