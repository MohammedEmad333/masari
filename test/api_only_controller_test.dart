import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  test('API-only connections expose the task list without a calendar', () {
    final controller = AppController(CalendarRepository());
    final apiTask = Deadline(
      uid: 'moodle-api:4:9',
      title: 'Assignment',
      due: DateTime.utc(2030, 1, 1),
    );
    expect(controller.hasConnection, isFalse);
    controller.apiConnected = true;
    controller.apiDeadlines = [apiTask];
    expect(controller.hasConnection, isTrue);
    expect(controller.activeDeadlines, hasLength(1));
    expect(controller.activeDeadlines.single.stableKey, apiTask.stableKey);
    controller.completedIds.add(apiTask.stableKey);
    expect(controller.completedDeadlines, hasLength(1));
  });

  test('calendar connections continue to work without API', () {
    final controller = AppController(CalendarRepository());
    controller.calendarConnected = true;
    expect(controller.hasConnection, isTrue);
    expect(controller.apiConnected, isFalse);
  });
}
