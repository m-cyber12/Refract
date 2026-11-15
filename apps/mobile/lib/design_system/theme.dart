import 'package:flutter/material.dart';

/// A quiet, paper-and-ink interface with a vivid refracted blue accent.
class RefractTheme {
  RefractTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF111412) : const Color(0xFFF4F3EE);
    final surface = dark ? const Color(0xFF1C211F) : const Color(0xFFFFFEFA);
    final surfaceHigh = dark ? const Color(0xFF282E2B) : const Color(0xFFEAEAE4);
    final ink = dark ? const Color(0xFFF4F3E9) : const Color(0xFF191C1A);
    final muted = dark ? const Color(0xFFB8BDB7) : const Color(0xFF606661);
    final accent = dark ? const Color(0xFF91ACFF) : const Color(0xFF264FB7);
    final line = dark ? const Color(0xFF414943) : const Color(0xFFDADDD5);
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
      primary: accent, surface: surface, onSurface: ink, onSurfaceVariant: muted,
      surfaceContainerHighest: surfaceHigh, outlineVariant: line,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.0, color: ink),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, color: ink),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: ink),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45, color: ink),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text,
      appBarTheme: AppBarTheme(backgroundColor: background, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface, indicatorColor: accent.withValues(alpha: dark ? 0.23 : 0.13),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        height: 70,
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0, margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: line))),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surface, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: accent, foregroundColor: dark ? const Color(0xFF101A35) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      )),
      chipTheme: base.chipTheme.copyWith(shape: StadiumBorder(side: BorderSide(color: line)),
        backgroundColor: surface, selectedColor: accent.withValues(alpha: 0.16)),
    );
  }
}
