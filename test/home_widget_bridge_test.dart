import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/home_widget_bridge.dart';

void main() {
  final now = DateTime.utc(2030, 1, 1, 12);
  final past = Deadline(
    uid: 'past',
    title: 'Old',
    due: now.subtract(const Duration(hours: 1)),
  );
  final soon = Deadline(
    uid: 'soon',
    title: 'Soon',
    due: now.add(const Duration(hours: 1)),
  );
  final later = Deadline(
    uid: 'later',
    title: 'Later',
    due: now.add(const Duration(days: 1)),
  );

  test('picks earliest uncompleted upcoming task', () {
    expect(
      HomeWidgetBridge.nextDeadline([later, past, soon], {}, now)?.uid,
      'soon',
    );
  });

  test('widget selects manual-only tasks without an iCalendar connection', () {
    final controller = AppController(CalendarRepository());
    controller.manualDeadlines = [later, soon];

    expect(controller.hasConnection, isFalse);
    expect(
      HomeWidgetBridge.nextDeadline(
        controller.allDeadlines,
        controller.completedIds,
        now,
      )?.uid,
      'soon',
    );
  });

  test('widget ignores completed API tasks and retains manual tasks', () {
    final controller = AppController(CalendarRepository());
    controller.apiDeadlines = [soon];
    controller.manualDeadlines = [later];
    controller.completedIds = {'soon'};

    expect(
      HomeWidgetBridge.nextDeadline(
        controller.allDeadlines,
        controller.completedIds,
        now,
      )?.uid,
      'later',
    );
  });

  test('skips completed tasks and returns none when no upcoming tasks', () {
    expect(
      HomeWidgetBridge.nextDeadline([soon, later], {'soon'}, now)?.uid,
      'later',
    );
    expect(HomeWidgetBridge.nextDeadline([past, soon], {'soon'}, now), isNull);
  });
}
