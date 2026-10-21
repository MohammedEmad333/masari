import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public repository links use Masari', () {
    final readme = File('README.md').readAsStringSync();
    final path = '.github/ISSUE_TEMPLATE/config.yml';
    final issueConfig = File(path).readAsStringSync();

    expect(readme.contains('MohammedEmad333/masari'), true);
    expect(readme.contains('MohammedEmad333/moodle-reminder'), false);
    expect(issueConfig.contains('MohammedEmad333/masari'), true);
    expect(issueConfig.contains('MohammedEmad333/moodle-reminder'), false);
  });
}
