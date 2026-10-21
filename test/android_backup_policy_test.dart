import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secure token backups are excluded on Android 11 and older', () {
    final policy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    expect(policy, contains('domain="sharedpref"'));
    expect(policy, contains('path="FlutterSecureStorage"'));
  });

  test('secure token backups are excluded on Android 12 and newer', () {
    final policy = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(policy, contains('<cloud-backup>'));
    expect(policy, contains('<device-transfer>'));
    expect(
      'path="FlutterSecureStorage"'.allMatches(policy).length,
      2,
    );
  });

  test('Android manifest references both backup exclusion policies', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });
}
