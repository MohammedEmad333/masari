import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/ics_parser.dart';
import 'package:moodle_reminder/services/notification_text.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('ar'));

  final due = DateTime(2030, 10, 23, 20, 40);
  final task = Deadline(
    uid: 'manual-notification',
    title: 'تجربة الإشعارات',
    course: 'الذكاء الاصطناعي',
    due: due,
  );

  test('Arabic reminders translate fixed copy and keep user task names', () {
    expect(
      NotificationText.dueSoon(task, arabic: true),
      'اقترب موعد: تجربة الإشعارات',
    );
    expect(
      NotificationText.dueNow(task, arabic: true),
      'حان موعد: تجربة الإشعارات',
    );
    expect(NotificationText.remainingMinutes(5, arabic: true), 'تبقّى 5 دقائق');
    expect(NotificationText.remainingHours(6, arabic: true), 'تبقّى 6 ساعات');
    expect(NotificationText.testTitle(arabic: true), 'إشعارات مساري جاهزة');
    expect(NotificationText.testBody(arabic: true), contains('مساري'));
    final body = NotificationText.body(
      task,
      NotificationText.remainingMinutes(5, arabic: true),
      arabic: true,
    );
    expect(body, isNot(contains('Due soon')));
    expect(body, contains('الذكاء الاصطناعي'));
    expect(body, contains('تبقّى 5 دقائق'));
    expect(body, contains(formatDue(due, arabic: true)));
    expect(body, isNot(contains('remaining')));
  });

  test('English reminders remain English while Moodle names are unchanged', () {
    expect(
      NotificationText.dueSoon(task, arabic: false),
      'Due soon: تجربة الإشعارات',
    );
    expect(
      NotificationText.remainingMinutes(5, arabic: false),
      '5 minutes remaining',
    );
    expect(
      NotificationText.remainingHours(1, arabic: false),
      '1 hour remaining',
    );
    expect(
      NotificationText.testTitle(arabic: false),
      'Masari notifications are ready',
    );
    expect(
      NotificationText.testBody(arabic: false),
      isNot(contains('Moodle Reminder')),
    );
    final english = formatDue(due);
    final arabic = formatDue(due, arabic: true);
    expect(english, isNot(arabic));
  });
}
