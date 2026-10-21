import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/main.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  testWidgets('startup paints a loading frame and offers error recovery', (
    tester,
  ) async {
    final controller = AppController(CalendarRepository());

    // Rendering must not require native Android notification or WorkManager
    // channels to be available before the first Flutter frame.
    await tester.pumpWidget(MoodleReminderApp(controller: controller));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // A failed saved-data initialization must render a recoverable screen,
    // rather than leaving a spinner/splash screen visible indefinitely.
    controller.reportStartupError();
    await tester.pump();

    expect(find.text('Masari could not load your saved data.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controller.clearStartupError();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
