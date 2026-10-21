import '../models/deadline.dart';
import 'moodle_deadline_merger.dart';

/// The single source of truth for reminders shown in the app and background
/// scheduling. Keep the iCalendar/API deduplication semantics consistent.
class DeadlineCollection {
  const DeadlineCollection._();

  static List<Deadline> combine({
    required List<Deadline> calendar,
    required List<Deadline> api,
    required List<Deadline> session,
    required List<Deadline> manual,
  }) {
    return <Deadline>[
      ...MoodleDeadlineMerger.merge(calendar, api),
      ...session,
      ...manual,
    ]..sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      return priority != 0 ? priority : a.due.compareTo(b.due);
    });
  }
}
