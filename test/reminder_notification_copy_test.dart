import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/reminder_notification_copy.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final deadline = Deadline(
    uid: 'manual-bilingual',
    title: 'تجربة الإشعارات',
    course: 'Computer Science',
    due: DateTime(2030, 10, 23, 20, 40),
  );

  test('Arabic notifications keep Moodle task/course content unchanged', () {
    expect(
      ReminderNotificationCopy.upcomingTitle(deadline, arabic: true),
      'اقترب موعد: تجربة الإشعارات',
    );
    expect(
      ReminderNotificationCopy.dueTitle(deadline, arabic: true),
      'حان موعد: تجربة الإشعارات',
    );
    final body = ReminderNotificationCopy.body(
      deadline,
      ReminderNotificationCopy.offsetMinutes(5, arabic: true),
      arabic: true,
    );
    expect(body, contains('5 دقائق متبقية'));
    expect(body, contains('Computer Science'));
    expect(body, isNot(contains('remaining')));
    expect(body, isNot(contains('Oct')));
  });

  test('English notifications stay English without translating task title', () {
    expect(
      ReminderNotificationCopy.upcomingTitle(deadline, arabic: false),
      'Due soon: تجربة الإشعارات',
    );
    expect(
      ReminderNotificationCopy.offsetMinutes(15, arabic: false),
      '15 minutes remaining',
    );
    expect(
      ReminderNotificationCopy.offsetHours(24, arabic: false),
      '1 day remaining',
    );
    expect(
      ReminderNotificationCopy.body(
        deadline,
        ReminderNotificationCopy.offsetMinutes(15, arabic: false),
        arabic: false,
      ),
      contains('Oct 23'),
    );
  });

  test('Arabic reminder units cover minutes, hours and days', () {
    expect(
      ReminderNotificationCopy.offsetMinutes(1, arabic: true),
      'دقيقة واحدة متبقية',
    );
    expect(
      ReminderNotificationCopy.offsetMinutes(15, arabic: true),
      '15 دقيقة متبقية',
    );
    expect(
      ReminderNotificationCopy.offsetHours(2, arabic: true),
      'ساعتان متبقيان',
    );
    expect(
      ReminderNotificationCopy.offsetHours(24, arabic: true),
      'يوم واحدة متبقية',
    );
  });

  test('test notifications use current Masari name in both languages', () {
    expect(
      ReminderNotificationCopy.getTestTitle(arabic: true),
      contains('مساري'),
    );
    expect(
      ReminderNotificationCopy.getTestBody(arabic: true),
      contains('مساري'),
    );
    expect(
      ReminderNotificationCopy.getTestTitle(arabic: false),
      contains('Masari'),
    );
    expect(
      ReminderNotificationCopy.getTestBody(arabic: false),
      isNot(contains('Moodle Reminder')),
    );
  });
}
