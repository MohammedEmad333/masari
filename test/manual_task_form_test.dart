import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/manual_task_form.dart';

void main() {
  test('date and time selection preserves local calendar values', () {
    final due = manualTaskDue(
      DateTime(2030, 7, 8),
      const TimeOfDay(hour: 19, minute: 5),
    );
    expect(due, DateTime(2030, 7, 8, 19, 5));
  });

  test('empty title and past deadlines are rejected', () {
    final now = DateTime(2030, 7, 8, 19);
    expect(
      validateManualTask('   ', now.add(const Duration(hours: 1)), now: now),
      ManualTaskValidationError.titleRequired,
    );
    expect(
      validateManualTask('Quiz', now, now: now),
      ManualTaskValidationError.dueInPast,
    );
    expect(
      validateManualTask('Quiz', now.add(const Duration(minutes: 5)), now: now),
      isNull,
    );
  });

  test('default deadline is in the future and rounded to five minutes', () {
    final now = DateTime(2030, 7, 8, 19, 58);
    final due = defaultManualTaskDue(now);
    expect(due.isAfter(now), isTrue);
    expect(due.minute % 5, 0);
    expect(due, DateTime(2030, 7, 8, 21));
  });
}
