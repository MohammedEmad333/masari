import '../models/deadline.dart';
import 'ics_parser.dart';

/// User-facing notification copy; source-provided task/course names are
/// preserved exactly as entered or returned by Moodle.
class NotificationText {
  const NotificationText._();

  static String testTitle({required bool arabic}) =>
      arabic ? 'إشعارات مساري جاهزة' : 'Masari notifications are ready';

  static String testBody({required bool arabic}) => arabic
      ? 'سيُذكّرك مساري بمواعيد مهامك القادمة.'
      : 'Masari can remind you before upcoming deadlines.';

  static String dueSoon(Deadline deadline, {required bool arabic}) =>
      arabic ? 'اقترب موعد: ${deadline.title}' : 'Due soon: ${deadline.title}';

  static String dueNow(Deadline deadline, {required bool arabic}) =>
      arabic ? 'حان موعد: ${deadline.title}' : 'Deadline now: ${deadline.title}';

  static String remainingHours(int hours, {required bool arabic}) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return arabic
          ? 'تبقّى $days يوم'
          : '$days ${days == 1 ? 'day' : 'days'} remaining';
    }
    return arabic
        ? 'تبقّى $hours ساعة'
        : '$hours ${hours == 1 ? 'hour' : 'hours'} remaining';
  }

  static String remainingMinutes(int minutes, {required bool arabic}) {
    if (minutes % 60 == 0) {
      return remainingHours(minutes ~/ 60, arabic: arabic);
    }
    return arabic
        ? 'تبقّى $minutes دقيقة'
        : '$minutes ${minutes == 1 ? 'minute' : 'minutes'} remaining';
  }

  static String body(
    Deadline deadline,
    String prefix, {
    required bool arabic,
  }) {
    final course = deadline.course.isEmpty ? '' : '${deadline.course} • ';
    return '$prefix • $course${formatDue(deadline.due, arabic: arabic)}';
  }
}
