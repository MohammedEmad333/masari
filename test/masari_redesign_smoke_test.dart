import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/navigation/masari_navigation.dart';
import 'package:moodle_reminder/screens/masari_assistant_composer.dart';
import 'package:moodle_reminder/screens/masari_more_quick_access.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets('five destination shell remains usable at enlarged text size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = MasariTab.home.index;

      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, update) => Scaffold(
                body: const Center(child: Text('Content')),
                bottomNavigationBar: MasariPrimaryNavigation(
                  selectedIndex: current,
                  arabic: arabic,
                  onDestinationSelected: (index) =>
                      update(() => current = index),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(current, MasariTab.more.index);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(current, MasariTab.schedule.index);
      expect(tester.takeException(), isNull);
    });

    testWidgets('More actions and compact assistant disclosure remain accessible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final visits = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.dark,
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MasariMoreQuickAccess(
                    arabic: arabic,
                    masariAccountEnabled: true,
                    onAccount: () => visits.add('account'),
                    onBackup: () => visits.add('backup'),
                    onTaskPlans: () => visits.add('plans'),
                    onAssistant: () => visits.add('assistant'),
                  ),
                  MasariAssistantComposer(
                    controller: controller,
                    arabic: arabic,
                    loading: false,
                    onSend: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final action in [
        ('account', arabic ? 'حساب مساري' : 'Masari account'),
        ('backup', arabic ? 'النسخ الاحتياطي السحابي' : 'Cloud backup'),
        ('plans', arabic ? 'خطط المهام' : 'Task plans'),
        ('assistant', arabic ? 'المساعد الدراسي' : 'Study assistant'),
      ]) {
        final target = find.text(action.$2);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump();
        expect(visits.last, action.$1);
      }
      expect(find.text('Assistant privacy'), findsNothing);
      expect(find.byType(MasariAssistantComposer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
