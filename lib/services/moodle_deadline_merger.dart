import '../models/deadline.dart';

/// Prefer iCalendar events when the same assignment is returned by Moodle API.
class MoodleDeadlineMerger {
  const MoodleDeadlineMerger._();

  static String _key(Deadline item) {
    final course = item.course.trim().toLowerCase();
    final title = item.title.trim().toLowerCase();
    final minute = item.due.toUtc().millisecondsSinceEpoch ~/ 60000;
    return '$course|$title|$minute';
  }

  static List<Deadline> merge(List<Deadline> calendar, List<Deadline> api) {
    final known = calendar.map(_key).toSet();
    final combined = <Deadline>[...calendar];
    for (final item in api) {
      if (known.add(_key(item))) combined.add(item);
    }
    return combined..sort((a, b) => a.due.compareTo(b.due));
  }
}
