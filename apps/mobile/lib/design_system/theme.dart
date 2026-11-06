import 'package:flutter/material.dart';

import 'tokens.dart';

class RefractTheme {
  RefractTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: RefractColors.obsidian,
      colorScheme: const ColorScheme.dark(
        primary: RefractColors.prismCyan,
        secondary: RefractColors.spectralViolet,
        surface: RefractColors.graphite,
        surfaceContainerHighest: RefractColors.elevated,
        onSurface: RefractColors.softWhite,
        onSurfaceVariant: RefractColors.muted,
        error: RefractColors.signalAmber,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: RefractColors.softWhite,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: RefractColors.graphite,
        indicatorColor: RefractColors.prismCyan.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: RefractColors.graphite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RefractColors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: RefractColors.softWhite,
        displayColor: RefractColors.softWhite,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: RefractColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: RefractColors.prismCyan,
        secondary: RefractColors.spectralViolet,
        surface: RefractColors.lightSurface,
        onSurface: RefractColors.lightText,
        onSurfaceVariant: RefractColors.lightMuted,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: RefractColors.lightText,
        displayColor: RefractColors.lightText,
      ),
    );
  }
}
