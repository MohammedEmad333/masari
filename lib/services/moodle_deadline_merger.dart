import '../models/deadline.dart';

/// Prefer iCalendar events when the same assignment is returned by Moodle API.
class MoodleDeadlineMerger {
  const MoodleDeadlineMerger._();

  static List<Deadline> merge(List<Deadline> calendar, List<Deadline> api) {
    String key(Deadline item) =>
        '${item.course.trim().toLowerCase()}|${item.title.trim().toLowerCase()}|${item.due.toUtc().millisecondsSinceEpoch ~/ 60000}';
    final known = calendar.map(key).toSet();
    return [...calendar, for (final item in api) if (known.add(key(item))) item]
      ..sort((a, b) => a.due.compareTo(b.due));
  }
}
