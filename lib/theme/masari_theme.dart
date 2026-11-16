import 'package:flutter/material.dart';

/// Masari 2.3 foundations. See docs/brand/MASARI_VISUAL_IDENTITY.md.
abstract final class MasariColors {
  static const primary = Color(0xFF0D63C8);
  static const navy = Color(0xFF102843);
  static const teal = Color(0xFF17A398);
  static const gold = Color(0xFFF3B95F);
  static const canvasLight = Color(0xFFF4F7FB);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const canvasDark = Color(0xFF0C1628);
  static const surfaceDark = Color(0xFF172B45);
  static const primaryDark = Color(0xFF8DBBFF);
}

abstract final class MasariSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class MasariRadii {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
}

abstract final class MasariTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? MasariColors.primaryDark : MasariColors.primary;
    final canvas = dark ? MasariColors.canvasDark : MasariColors.canvasLight;
    final surface = dark ? MasariColors.surfaceDark : MasariColors.surfaceLight;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: MasariColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? MasariColors.canvasDark : Colors.white,
          surface: surface,
          onSurface: dark ? Colors.white : MasariColors.navy,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MasariRadii.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MasariRadii.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MasariSpacing.lg,
          vertical: MasariSpacing.md,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MasariRadii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MasariRadii.md),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.14),
        height: 80,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
    );
  }
}
