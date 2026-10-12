import '../models/deadline.dart';

/// Combines calendar feeds without conflating event IDs from different sources.
///
/// [sourceId] is a stable, opaque identifier assigned to each additional feed.
/// The primary feed has an empty source ID for backward compatibility.
class CalendarSourceMerger {
  const CalendarSourceMerger._();

  static List<Deadline> merge(Map<String, List<Deadline>> feeds) {
    final events = <String, Deadline>{};
    for (final entry in feeds.entries) {
      final sourceId = entry.key;
      for (final deadline in entry.value) {
        final key = sourceId.isEmpty
            ? deadline.stableKey
            : '$sourceId:${deadline.stableKey}';
        events[key] = sourceId.isEmpty
            ? deadline
            : Deadline(
                uid: key,
                title: deadline.title,
                due: deadline.due,
                description: deadline.description,
                course: deadline.course,
                url: deadline.url,
                location: deadline.location,
                status: deadline.status,
                sequence: deadline.sequence,
                priority: deadline.priority,
                lastModified: deadline.lastModified,
              );
      }
    }
    return events.values.toList()..sort((a, b) => a.due.compareTo(b.due));
  }
}
