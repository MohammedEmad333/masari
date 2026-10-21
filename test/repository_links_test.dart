import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public repository links use the Masari repository name', () {
    for (final path in [
      'README.md',
      '.github/ISSUE_TEMPLATE/config.yml',
    ]) {
      final content = File(path).readAsStringSync();

      expect(
        content,
        isNot(contains('MohammedEmad333/moodle-reminder')),
        reason: 'Outdated GitHub URL in $path',
      );
      expect(content, contains('MohammedEmad333/masari'));
    }
  });
}
