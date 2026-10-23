import 'package:timezone/timezone.dart' as tz;

/// Convert an existing absolute deadline instant to UTC for one-shot alarms.
///
/// Android interprets zonedSchedule's timezone identifier along with its
/// wall-clock fields. UTC preserves the same instant even if the device's
/// timezone plugin returns a non-IANA alias or fails on an OEM ROM.
/// Deadline dates must already be parsed into correct absolute instants.
tz.TZDateTime reminderScheduledInstant(DateTime when) {
  return tz.TZDateTime.from(when, tz.UTC);
}
