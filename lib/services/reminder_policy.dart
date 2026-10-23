import '../models/deadline.dart';

/// Per-deadline overrides take precedence over global reminder offsets.
/// An empty override intentionally disables early alerts for that deadline.
List<int> offsetsForDeadline(
  Deadline deadline,
  List<int> defaults,
  Map<String, List<int>> overrides,
) {
  final selected = overrides[deadline.stableKey] ?? defaults;
  return selected.where((hours) => hours > 0).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
}

List<DateTime> upcomingReminderTimes(
  Deadline deadline,
  List<int> defaults,
  Map<String, List<int>> overrides, {
  required DateTime now,
}) {
  if (!deadline.due.isAfter(now) || deadline.reminderMinutesBefore == -1) {
    return const [];
  }
  final minutes = deadline.reminderMinutesBefore;
  final early = minutes != null
      ? <DateTime>[
          if (minutes > 0 &&
              deadline.due.subtract(Duration(minutes: minutes)).isAfter(now))
            deadline.due.subtract(Duration(minutes: minutes)),
        ]
      : <DateTime>[
          for (final hours in offsetsForDeadline(deadline, defaults, overrides))
            if (deadline.due.subtract(Duration(hours: hours)).isAfter(now))
              deadline.due.subtract(Duration(hours: hours)),
        ];
  return [...early, deadline.due];
}
