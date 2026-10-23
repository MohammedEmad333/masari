import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/reminder_schedule_time.dart';

void main() {
  test('UTC alarm preserves an absolute UTC deadline instant', () {
    final instant = DateTime.utc(2030, 10, 23, 22, 40);
    final scheduled = reminderScheduledInstant(instant);
    expect(scheduled.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
    expect(scheduled.timeZoneOffset, Duration.zero);
  });

  test('UTC alarm preserves the same instant from local DateTime', () {
    final local = DateTime(2030, 10, 23, 22, 40);
    final scheduled = reminderScheduledInstant(local);
    expect(scheduled.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    expect(scheduled.timeZoneOffset, Duration.zero);
  });
}
