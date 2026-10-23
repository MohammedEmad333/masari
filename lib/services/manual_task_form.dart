import 'package:flutter/material.dart';

enum ManualTaskValidationError { titleRequired, dueInPast }

/// Build the actual local deadline from independently selected date and time.
DateTime manualTaskDue(DateTime day, TimeOfDay time) {
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

ManualTaskValidationError? validateManualTask(
  String title,
  DateTime due, {
  required DateTime now,
}) {
  if (title.trim().isEmpty) return ManualTaskValidationError.titleRequired;
  if (!due.isAfter(now)) return ManualTaskValidationError.dueInPast;
  return null;
}

/// Advance to the next five-minute boundary at least one hour from now.
DateTime defaultManualTaskDue(DateTime now) {
  final later = now.add(const Duration(hours: 1));
  final roundedMinutes = ((later.minute + 4) ~/ 5) * 5;
  return DateTime(later.year, later.month, later.day, later.hour, roundedMinutes);
}
