import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official Android APK keeps a valid notification drawable', () {
    final icon = File(
      'android/app/src/main/res/drawable/masari_notification.xml',
    ).readAsStringSync();
    final keep = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    final service = File(
      'lib/services/notification_service.dart',
    ).readAsStringSync();

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
    final service = File(
      'lib/services/notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('reminderScheduledInstant(when)'));
    expect(service, isNot(contains('FlutterTimezone.getLocalTimezone()')));
    expect(service, contains('static Future<void> showTest()'));
  });
}
