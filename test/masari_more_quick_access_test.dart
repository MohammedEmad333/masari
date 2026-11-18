import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_more_quick_access.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets('More quick access shows all destinations in ${arabic ? 'RTL' : 'LTR'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.light,
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: SingleChildScrollView(
                child: MasariMoreQuickAccess(
                  arabic: arabic,
                  masariAccountEnabled: true,
                  onAccount: () => calls.add('account'),
                  onBackup: () => calls.add('backup'),
                  onTaskPlans: () => calls.add('plans'),
                  onAssistant: () => calls.add('assistant'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(4));
      expect(find.text(arabic ? 'حساب مساري' : 'Masari account'), findsOneWidget);
      expect(find.text(arabic ? 'المساعد الدراسي' : 'Study assistant'), findsOneWidget);
      expect(
        find.byIcon(arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
        findsNWidgets(4),
      );
      await tester.tap(find.text(arabic ? 'حساب مساري' : 'Masari account'));
      await tester.tap(find.text(arabic ? 'النسخ الاحتياطي السحابي' : 'Cloud backup'));
      await tester.tap(find.text(arabic ? 'خطط المهام' : 'Task plans'));
      await tester.tap(find.text(arabic ? 'المساعد الدراسي' : 'Study assistant'));
      expect(calls, ['account', 'backup', 'plans', 'assistant']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Google account mode retains account destination', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MasariMoreQuickAccess(
            arabic: false,
            masariAccountEnabled: false,
            onAccount: () {},
            onBackup: () {},
            onTaskPlans: () {},
            onAssistant: () {},
          ),
        ),
      ),
    );
    expect(find.text('Google account'), findsOneWidget);
    expect(find.text('Masari account'), findsNothing);
  });
}
