import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  test('every Android variant uses one application ID', () {
    final gradle = readProjectFile('android/app/build.gradle.kts');

    expect(gradle, contains('System.getenv("PLAY_STORE_BUILD") == "true"'));
    expect(gradle, contains('applicationId = "com.mohammedemad333.masari"'));
    expect(gradle, contains('"com.mohammedemad333.masari"'));
    expect(gradle, isNot(contains('applicationId = if (playStoreBuild)')));
    expect(gradle, contains('signingConfig = if (!ciSmokeBuild) {'));
    expect(gradle, contains('val playSigningRequested = !ciSmokeBuild'));
  });

  test('Play publishing workflow opts into the signed Store build', () {
    final workflow = readProjectFile('.github/workflows/google-play-aab.yml');

    expect(workflow, contains("PLAY_STORE_BUILD: 'true'"));
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('PLAY_UPLOAD_KEYSTORE_BASE64'));
  });

  test('Native Android classes remain in the Gradle namespace', () {
    final gradle = readProjectFile('android/app/build.gradle.kts');
    final activity = readProjectFile(
      'android/app/src/main/kotlin/com/example/moodle_reminder/MainActivity.kt',
    );
    final provider = readProjectFile(
      'android/app/src/main/kotlin/com/example/moodle_reminder/MoodleWidgetProvider.kt',
    );

    expect(gradle, contains('namespace = "com.example.moodle_reminder"'));
    expect(activity, startsWith('package com.example.moodle_reminder'));
    expect(provider, startsWith('package com.example.moodle_reminder'));
    final manifest = readProjectFile(
      'android/app/src/main/AndroidManifest.xml',
    );
    expect(manifest, contains('com.example.moodle_reminder.MainActivity'));
    expect(
      manifest,
      contains('com.example.moodle_reminder.MoodleWidgetProvider'),
    );
  });
}
