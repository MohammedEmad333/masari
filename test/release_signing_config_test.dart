import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official releases use the registered Masari ID and stable key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final publish = File(
      '.github/workflows/publish-release.yml',
    ).readAsStringSync();
    final manual = File('.github/workflows/release.yml').readAsStringSync();

    expect(gradle, contains('"com.mohammedemad333.masari"'));
    for (final workflow in [publish, manual]) {
      expect(workflow, contains("PLAY_STORE_BUILD: 'true'"));
      expect(workflow, contains('secrets.PLAY_UPLOAD_KEYSTORE_BASE64'));
      expect(workflow, contains('secrets.PLAY_KEY_PASSWORD'));
      expect(workflow, contains('apksigner'));
      expect(workflow, contains("package: name='com.mohammedemad333.masari'"));
    }
  });

  test('legacy CI APK cannot be mistaken for a distributable release', () {
    final ci = File('.github/workflows/flutter-ci.yml').readAsStringSync();
    final publish = File(
      '.github/workflows/publish-release.yml',
    ).readAsStringSync();

    expect(ci, isNot(contains('actions/upload-artifact@')));
    expect(ci, contains('Smoke-build legacy APK (not for distribution)'));
    expect(publish, isNot(contains('moodle-reminder-release-apk')));
    expect(publish, isNot(contains('--clobber')));
  });

  test('next Masari release increments its Android version code', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(yaml, contains('version: 2.2.3+7'));
  });
}
