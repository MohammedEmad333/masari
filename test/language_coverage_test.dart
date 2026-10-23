import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test and scheduled alerts use one localized notification system', () {
    final service = File(
      'lib/services/notification_service.dart',
    ).readAsStringSync();
    final controller = File('lib/app_controller.dart').readAsStringSync();
    final background = File(
      'lib/services/background_sync_service.dart',
    ).readAsStringSync();
    final home = File('lib/screens/home_shell.dart').readAsStringSync();

    expect(service, contains('NotificationText.testTitle(arabic: arabic)'));
    expect(service, contains('NotificationText.remainingMinutes'));
    expect(service, contains('NotificationText.remainingHours'));
    expect(service, isNot(contains('Moodle Reminder can alert')));
    expect(controller, contains("arabic: locale.languageCode == 'ar'"));
    expect(background, contains("(await repository.loadLocale()) == 'ar'"));
    expect(home, contains('NotificationService.showTest(arabic: _ar)'));
  });

  test('native widget and course chooser follow Masari language choice', () {
    final bridge = File(
      'lib/services/home_widget_bridge.dart',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/example/moodle_reminder/MoodleWidgetProvider.kt',
    ).readAsStringSync();
    final chooser = File(
      'android/app/src/main/kotlin/com/example/moodle_reminder/MainActivity.kt',
    ).readAsStringSync();
    final shareScreen = File(
      'lib/screens/local_courses_screen.dart',
    ).readAsStringSync();

    expect(bridge, contains("'language': languageCode == 'ar' ? 'ar' : 'en'"));
    expect(kotlin, contains('Locale.forLanguageTag(language)'));
    expect(chooser, contains('مشاركة المساق'));
    expect(shareScreen, contains("'language': widget.arabic ? 'ar' : 'en'"));
  });

  test('web view errors are localized rather than raw system messages', () {
    for (final path in [
      'lib/screens/moodle_calendar_browser.dart',
      'lib/screens/moodle_session_pilot_screen.dart',
    ]) {
      final code = File(path).readAsStringSync();
      expect(code, isNot(contains('_error = error.description')));
      expect(code, contains('تعذّر تحميل صفحة Moodle'));
    }
  });
}
