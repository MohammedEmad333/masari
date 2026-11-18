import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_assistant_privacy_notice.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  for (final arabic in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'assistant privacy guidance fits narrow screens in ${arabic ? 'Arabic' : 'English'}',
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
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: MasariAssistantPrivacyNotice(arabic: arabic),
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(
            find.text(arabic ? 'خصوصية المساعد' : 'Assistant privacy'),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.privacy_tip_outlined), findsOneWidget);
          expect(find.byType(Card), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('privacy notice mentions external provider and data limitations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MasariAssistantPrivacyNotice(arabic: false),
        ),
      ),
    );

    expect(find.textContaining('TokenRouter'), findsOneWidget);
    expect(find.textContaining('cannot read tasks'), findsOneWidget);
  });
}
