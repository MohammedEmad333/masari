import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/pomodoro_clock.dart';

void main() {
  test('focus and break have conventional durations', () {
    expect(PomodoroClock.focus, const Duration(minutes: 25));
    expect(PomodoroClock.shortBreak, const Duration(minutes: 5));
  });

  test('countdown never becomes negative', () {
    expect(
      PomodoroClock.remaining(
        session: PomodoroClock.focus,
        elapsed: const Duration(minutes: 26),
      ),
      Duration.zero,
    );
    expect(
      PomodoroClock.remaining(
        session: PomodoroClock.shortBreak,
        elapsed: const Duration(minutes: 2),
      ),
      const Duration(minutes: 3),
    );
  });

  test('clock display zero pads minutes and seconds', () {
    expect(PomodoroClock.display(const Duration(minutes: 5, seconds: 9)), '05:09');
    expect(PomodoroClock.display(Duration.zero), '00:00');
  });
}
