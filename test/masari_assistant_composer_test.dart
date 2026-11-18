import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_assistant_composer.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets(
      'question can be sent without a checkbox in ${arabic ? 'Arabic' : 'English'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var sends = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: MasariTheme.light,
            home: Directionality(
              textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: MasariAssistantComposer(
                    controller: controller,
                    arabic: arabic,
                    loading: false,
                    onSend: () => sends++,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.text(arabic ? 'اسأل المساعد' : 'Ask AI'), findsOneWidget);
        expect(
          find.text(
            arabic
                ? 'بالضغط على «اسأل المساعد»، سيتم إرسال نص سؤالك إلى خدمة الذكاء الاصطناعي الخارجية.'
                : 'Tapping “Ask AI” sends your question to the external AI service.',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );

        await tester.tap(find.text(arabic ? 'اسأل المساعد' : 'Ask AI'));
        expect(sends, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('composer is disabled only while a request is loading', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MasariTheme.dark,
        home: Scaffold(
          body: MasariAssistantComposer(
            controller: controller,
            arabic: false,
            loading: true,
            onSend: () {},
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
