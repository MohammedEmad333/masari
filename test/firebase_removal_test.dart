import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter runtime and package manifest do not depend on Firebase', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('firebase_core:')));
    expect(pubspec, isNot(contains('firebase_auth:')));
    expect(pubspec, isNot(contains('firebase_app_check:')));
    expect(pubspec, isNot(contains('cloud_firestore:')));

    for (final directory in [Directory('lib'), Directory('android')]) {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.gradle') &&
            !entity.path.endsWith('.kts') &&
            !entity.path.endsWith('.xml')) {
          continue;
        }
        final source = entity.readAsStringSync();
        expect(source, isNot(contains('package:firebase_')));
        expect(source, isNot(contains('package:cloud_firestore/')));
      }
    }
  });

  test('server runtime and Compose files do not configure Firebase', () {
    for (final path in [
      'server/ai-proxy/index.mjs',
      'server/ai-proxy/accounts_index.mjs',
      'server/ai-proxy/core.mjs',
      'server/ai-proxy/compose.oracle.yaml',
      'server/ai-proxy/compose.oracle-postgres.yaml',
      'server/ai-proxy/package.json',
    ]) {
      final source = File(path).readAsStringSync().toLowerCase();
      for (final forbidden in [
        'firebase-admin',
        'firestore_quota',
        'createFirestoreQuota',
        'FIREBASE_PROJECT_ID',
        'GOOGLE_APPLICATION_CREDENTIALS',
        'getFirestore(',
        'getAuth(',
        'getAppCheck(',
        'x-firebase-appcheck',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '$path contains $forbidden',
        );
      }
    }
  });
}
