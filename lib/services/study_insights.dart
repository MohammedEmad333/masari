import '../models/deadline.dart';

/// Study dashboard calculations, independent of UI and the wall clock.
class StudyInsights {
  const StudyInsights._();

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<Deadline> forDay(Iterable<Deadline> tasks, DateTime day) =>
      tasks.where((task) => sameDay(task.due, day)).toList()
        ..sort((a, b) => a.due.compareTo(b.due));

  static Map<DateTime, List<Deadline>> week(
    Iterable<Deadline> tasks,
    DateTime anchor,
  ) {
    final start = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - DateTime.monday));
    return {
      for (var i = 0; i < 7; i++)
        start.add(Duration(days: i)):
            forDay(tasks, start.add(Duration(days: i))),
    };
  }

  /// Conflicts are distinct tasks with matching due dates/times.
  static List<List<Deadline>> conflicts(Iterable<Deadline> tasks) {
    final byDue = <DateTime, List<Deadline>>{};
    for (final task in tasks) {
      byDue.putIfAbsent(task.due, () => []).add(task);
    }
    return byDue.values.where((group) => group.length > 1).toList()
      ..sort((a, b) => a.first.due.compareTo(b.first.due));
  }

  static double completionRate(int completed, int total) =>
      total == 0 ? 0 : completed / total;
}
