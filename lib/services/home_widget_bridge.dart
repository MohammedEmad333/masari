import 'package:flutter/services.dart';

import '../models/deadline.dart';

class HomeWidgetBridge {
  const HomeWidgetBridge._();

  static const channel = MethodChannel('moodle_reminder/home_widget');

  static Deadline? nextDeadline(
    Iterable<Deadline> deadlines,
    Set<String> completedIds,
    DateTime now,
  ) {
    final pending =
        deadlines
            .where((task) => !completedIds.contains(task.stableKey))
            .where((task) => !task.due.isBefore(now))
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    return pending.isEmpty ? null : pending.first;
  }

  static Future<void> publish(
    Iterable<Deadline> deadlines,
    Set<String> completedIds,
  ) async {
    final next = nextDeadline(deadlines, completedIds, DateTime.now());
    await channel.invokeMethod<void>('updateDeadline', {
      'title': next?.title ?? '',
      'due': next?.due.millisecondsSinceEpoch ?? 0,
    });
  }
}
