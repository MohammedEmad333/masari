import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/navigation/masari_navigation.dart';

void main() {
  test('five destinations preserve the expected order', () {
    expect(
      MasariTab.values,
      [
        MasariTab.home,
        MasariTab.tasks,
        MasariTab.schedule,
        MasariTab.courses,
        MasariTab.more,
      ],
    );
  });

  for (final arabic in [false, true]) {
    testWidgets(
      'five-tab navigation handles taps in ${arabic ? 'Arabic' : 'English'}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var selected = MasariTab.home.index;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: const SizedBox.shrink(),
                  bottomNavigationBar: MasariPrimaryNavigation(
                    selectedIndex: selected,
                    arabic: arabic,
                    onDestinationSelected: (value) =>
                        setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(find.text(arabic ? 'جدولي' : 'Schedule'), findsOneWidget);
        expect(find.text(arabic ? 'المزيد' : 'More'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        expect(selected, MasariTab.more.index);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'schedule switches between calendar and weekly plan in ${arabic ? 'RTL' : 'LTR'}',
      (tester) async {
        var selected = MasariScheduleView.calendar;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Center(
                    child: MasariSchedulePicker(
                      value: selected,
                      arabic: arabic,
                      onChanged: (value) =>
                          setState(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text(arabic ? 'التقويم' : 'Calendar'), findsOneWidget);
        expect(find.text(arabic ? 'الأسبوع' : 'Week'), findsOneWidget);
        await tester.tap(find.text(arabic ? 'الأسبوع' : 'Week'));
        await tester.pumpAndSettle();
        expect(selected, MasariScheduleView.week);
        await tester.tap(find.text(arabic ? 'التقويم' : 'Calendar'));
        await tester.pumpAndSettle();
        expect(selected, MasariScheduleView.calendar);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
