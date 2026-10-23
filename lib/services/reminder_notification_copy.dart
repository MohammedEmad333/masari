import 'package:intl/intl.dart';

import '../models/deadline.dart';

/// User-facing notification copy. Preserve the original Moodle task title
/// and course name; only app-generated labels follow the selected language.
class ReminderNotificationCopy {
  const ReminderNotificationCopy._();

  static String upcomingTitle(Deadline deadline, {required bool arabic}) =>
      arabic
          ? 'اقترب موعد: ${deadline.title}'
          : 'Due soon: ${deadline.title}';

  static String dueTitle(Deadline deadline, {required bool arabic}) =>
      arabic
          ? 'حان موعد: ${deadline.title}'
          : 'Deadline now: ${deadline.title}';

  static String dueNow({required bool arabic}) =>
      arabic ? 'حان وقت الاستحقاق' : 'Due now';

  static String offsetHours(int hours, {required bool arabic}) {
    if (hours % 24 == 0) {
      return _quantity(hours ~/ 24, 'day', arabic: arabic);
    }
    return _quantity(hours, 'hour', arabic: arabic);
  }

  static String offsetMinutes(int minutes, {required bool arabic}) {
    if (minutes % 60 == 0) {
      return offsetHours(minutes ~/ 60, arabic: arabic);
    }
    return _quantity(minutes, 'minute', arabic: arabic);
  }

  static String _quantity(int amount, String unit, {required bool arabic}) {
    if (!arabic) {
      return '$amount $unit${amount == 1 ? '' : 's'} remaining';
    }
    final names = switch (unit) {
      'minute' => ['دقيقة', 'دقيقتان', 'دقائق'],
      'hour' => ['ساعة', 'ساعتان', 'ساعات'],
      _ => ['يوم', 'يومان', 'أيام'],
    };
    if (amount == 1) return '${names[0]} واحدة متبقية';
    if (amount == 2) return '${names[1]} متبقيان';
    if (amount >= 3 && amount <= 10) {
      return '$amount ${names[2]} متبقية';
    }
    return '$amount ${names[0]} متبقية';
  }

  static String body(
    Deadline deadline,
    String leading, {
    required bool arabic,
  }) {
    final course = deadline.course.isEmpty ? '' : '${deadline.course} • ';
    final due = DateFormat(
      arabic ? 'EEE، d MMM • h:mm a' : 'EEE, MMM d • h:mm a',
      arabic ? 'ar' : 'en',
    ).format(deadline.due);
    return '$leading • $course$due';
  }

  static String getTestTitle({required bool arabic}) =>
      arabic ? 'إشعارات مساري جاهزة' : 'Masari notifications are ready';

  static String getTestBody({required bool arabic}) => arabic
      ? 'يمكن لتطبيق مساري تنبيهك قبل مواعيد المهام القادمة.'
      : 'Masari can alert you before upcoming deadlines.';
}
