import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_assistant_composer.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets(
      'chat composer sends only after explicit action in ${arabic ? 'Arabic' : 'English'}',
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
            theme: MasariTheme.dark,
            home: Directionality(
              textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: Column(
                  children: [
                    const Expanded(child: SizedBox()),
                    MasariAssistantComposer(
                      controller: controller,
                      arabic: arabic,
                      loading: false,
                      onSend: () => sends++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Checkbox), findsNothing);
        expect(
          find.text(arabic ? 'اكتب سؤالك هنا...' : 'Message…'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            arabic
                ? 'سيتم إرسال نص سؤالك'
                : 'shares your question',
          ),
          findsOneWidget,
        );

        await tester.enterText(find.byType(TextField), 'Help me study');
        await tester.pump();
        expect(sends, 0);
        await tester.tap(find.byTooltip(arabic ? 'اسأل المساعد' : 'Ask AI'));
        await tester.pump();
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
    final sendButton = find.ancestor(
      of: find.byTooltip('Ask AI'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
  });
}
