import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/theme/masari_components.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final lighter = x > y ? x : y;
  final darker = x > y ? y : x;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('brand spacing and radii are ordered and stable', () {
    expect(MasariSpacing.xs, lessThan(MasariSpacing.sm));
    expect(MasariSpacing.sm, lessThan(MasariSpacing.md));
    expect(MasariSpacing.md, lessThan(MasariSpacing.lg));
    expect(MasariSpacing.lg, lessThan(MasariSpacing.xl));
    expect(MasariSpacing.xl, lessThan(MasariSpacing.xxl));
    expect(MasariRadii.sm, lessThan(MasariRadii.md));
    expect(MasariRadii.md, lessThan(MasariRadii.lg));
  });

  test('light and dark themes preserve usable text contrast', () {
    for (final theme in [MasariTheme.light, MasariTheme.dark]) {
      expect(theme.useMaterial3, isTrue);
      expect(
        contrastRatio(
          theme.colorScheme.onSurface,
          theme.colorScheme.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(
          theme.colorScheme.onPrimary,
          theme.colorScheme.primary,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(theme.navigationBarTheme.height, 80);
    }
    expect(MasariTheme.light.brightness, Brightness.light);
    expect(MasariTheme.dark.brightness, Brightness.dark);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'shared components render in $direction / $brightness at narrow width',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light
                  ? MasariTheme.light
                  : MasariTheme.dark,
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(MasariSpacing.lg),
                      children: const [
                        MasariSectionHeader(
                          title: 'المهام / Tasks',
                          count: '3',
                        ),
                        SizedBox(height: MasariSpacing.lg),
                        MasariEmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'لا توجد مهام',
                          description: 'Add your first task.',
                        ),
                        SizedBox(height: MasariSpacing.lg),
                        MasariSettingsSection(
                          title: 'Settings / الإعدادات',
                          child: Text('Theme / المظهر'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(find.text('المهام / Tasks'), findsOneWidget);
          expect(find.text('لا توجد مهام'), findsOneWidget);
          expect(find.text('Theme / المظهر'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
