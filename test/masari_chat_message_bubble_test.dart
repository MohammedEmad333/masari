import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_chat_message_bubble.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets(
      'chat message stays readable in ${arabic ? 'Arabic' : 'English'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: MasariTheme.dark,
            home: Directionality(
              textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MasariChatMessageBubble(
                    text: arabic
                        ? 'مرحبًا! كيف يمكنني مساعدتك؟'
                        : 'Hello! How can I help you?',
                    fromUser: false,
                    arabic: arabic,
                  ),
                ),
              ),
            ),
          ),
        );

        final selectable = tester.widget<SelectableText>(
          find.byType(SelectableText),
        );
        expect(selectable.textSpan!.style!.fontSize, 16);
        expect(find.textContaining(arabic ? 'مرحبًا' : 'Hello'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('error bubble uses theme error colors without custom styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MasariTheme.dark,
        home: const Scaffold(
          body: MasariChatMessageBubble(
            text: 'Unable to connect.',
            fromUser: false,
            arabic: false,
            isError: true,
          ),
        ),
      ),
    );

    expect(find.text('Unable to connect.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
