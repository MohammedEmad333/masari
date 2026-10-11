/// Immutable calculations for a Pomodoro focus/break countdown.
class PomodoroClock {
  const PomodoroClock._();

  static const focus = Duration(minutes: 25);
  static const shortBreak = Duration(minutes: 5);

  static Duration remaining({
    required Duration session,
    required Duration elapsed,
  }) {
    final result = session - elapsed;
    return result.isNegative ? Duration.zero : result;
  }

  static String display(Duration remaining) {
    final minutes = remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
