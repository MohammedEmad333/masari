import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official Android APK keeps a valid notification drawable', () {
    final icon = File(
      'android/app/src/main/res/drawable/masari_notification.xml',
    ).readAsStringSync();
    final keep = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync();
    final service = File('lib/services/notification_service.dart')
        .readAsStringSync();

    expect(icon, contains('<vector'));
    expect(icon, contains('android:pathData'));
    expect(keep, contains('@drawable/masari_notification'));
    expect(
      service,
      contains("AndroidInitializationSettings('masari_notification')"),
    );
    expect(service, isNot(contains("AndroidInitializationSettings('@mipmap")));
  });

  test('immediate notifications do not need device timezone resolution', () {
    final service = File('lib/services/notification_service.dart')
        .readAsStringSync();

    expect(service, contains('reminderScheduledInstant(when)'));
    expect(service, isNot(contains('FlutterTimezone.getLocalTimezone()')));
    expect(
      service,
      contains('static Future<void> showTest({bool arabic = false})'),
    );
  });

  test('notification plugin 23 retains Android reboot and alarm behavior', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final service = File('lib/services/notification_service.dart')
        .readAsStringSync();

    expect(pubspec, contains('flutter_local_notifications: ^23.0.0'));
    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('targetSdk = 36'));
    expect(settings, contains('version "9.1.1"'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(service, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
    expect(service, contains('await _plugin.cancelAll()'));
  });
}
