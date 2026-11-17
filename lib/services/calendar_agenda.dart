import '../models/deadline.dart';

/// Read-only agenda selectors. The caller supplies active deadlines, so
/// selecting a date never changes saved tasks or notification schedules.
List<Deadline> deadlinesOnDay(Iterable<Deadline> deadlines, DateTime day) {
  final result = deadlines.where((deadline) => _sameDay(deadline.due, day)).toList();
  result.sort((a, b) => a.due.compareTo(b.due));
  return result;
}

/// First future deadline on a later calendar day, ordered by due time.
Deadline? nextDeadlineAfterDay(Iterable<Deadline> deadlines, DateTime day) {
  final selectedDay = DateTime(day.year, day.month, day.day);
  final later = deadlines.where((deadline) {
    final due = deadline.due;
    return DateTime(due.year, due.month, due.day).isAfter(selectedDay);
  }).toList();
  later.sort((a, b) => a.due.compareTo(b.due));
  return later.isEmpty ? null : later.first;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
