import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_study_overview.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'study overview keeps all metrics visible on narrow screens',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? MasariTheme.dark : MasariTheme.light,
              home: Directionality(
                textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: MasariStudyOverview(
                        arabic: true,
                        completionPercent: 75,
                        dueSoonCount: 3,
                        overdueCount: 0,
                        conflictCount: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(find.text('75%'), findsOneWidget);
          expect(find.text('3'), findsOneWidget);
          expect(find.text('0'), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
          expect(find.byType(Card), findsNWidgets(4));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('English metrics keep their labels and zero counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MasariTheme.light,
        home: const Scaffold(
          body: MasariStudyOverview(
            arabic: false,
            completionPercent: 0,
            dueSoonCount: 0,
            overdueCount: 0,
            conflictCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Next 7 days'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Conflicts'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });
}
