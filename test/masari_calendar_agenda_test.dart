import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/screens/masari_agenda_day_header.dart';
import 'package:moodle_reminder/services/calendar_agenda.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  final first = Deadline(
    uid: 'first',
    title: 'Morning task',
    due: DateTime(2030, 3, 12, 9),
  );
  final later = Deadline(
    uid: 'later',
    title: 'Afternoon task',
    due: DateTime(2030, 3, 12, 14),
  );
  final next = Deadline(
    uid: 'next',
    title: 'Next day task',
    due: DateTime(2030, 3, 13, 10),
  );

  test('day agenda orders tasks chronologically, without mutating input', () {
    final input = [later, next, first];
    final selected = deadlinesOnDay(input, DateTime(2030, 3, 12));
    expect(selected.map((d) => d.uid).toList(), ['first', 'later']);
    expect(input.map((d) => d.uid).toList(), ['later', 'next', 'first']);
  });

  test('empty-day hint uses the next chronological deadline', () {
    final far = Deadline(
      uid: 'far',
      title: 'Later deadline',
      due: DateTime(2030, 3, 19),
    );
    expect(
      nextDeadlineAfterDay([far, next, first], DateTime(2030, 3, 12))?.uid,
      'next',
    );
    expect(nextDeadlineAfterDay([first], DateTime(2030, 3, 12)), isNull);
  });

  for (final arabic in [false, true]) {
    testWidgets('agenda Today action works with narrow RTL/LTR layouts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.light,
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: MasariAgendaDayHeader(
                dateLabel: arabic ? '12 مارس 2030' : 'March 12, 2030',
                eventCount: 2,
                isToday: false,
                arabic: arabic,
                onToday: () => taps++,
              ),
            ),
          ),
        ),
      );
      expect(find.text(arabic ? 'اليوم' : 'Today'), findsOneWidget);
      await tester.tap(find.text(arabic ? 'اليوم' : 'Today'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Today button is hidden when the selected date is today', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MasariAgendaDayHeader(
            dateLabel: 'Today',
            eventCount: 0,
            isToday: true,
            arabic: false,
            onToday: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.today_outlined), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });
}
