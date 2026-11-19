import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud backup uses explicit user action and no Moodle secrets', () {
    final source = File(
      'lib/services/optional_cloud_backup.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/cloud_backup_screen.dart',
    ).readAsStringSync();
    expect(source, contains('manualTasks'));
    expect(source, contains('plans'));
    expect(source, contains('task.title'));
    expect(source, isNot(contains('task.url')));
    expect(source, isNot(contains('calendarUrl')));
    expect(source, isNot(contains('MoodleApiCredentialsStore')));
    expect(screen, contains('onPressed: _busy ? null : _upload'));
    expect(screen, contains('onPressed: _busy ? null : _restore'));
  });

  test('Firestore rules limit access to the account owner', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    expect(rules, contains('request.auth.uid == userId'));
    expect(rules, contains("backupId == 'personal-v1'"));
  });
}
