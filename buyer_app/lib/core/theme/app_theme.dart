import 'package:flutter/material.dart';

abstract final class Palette {
  static const ink = Color(0xFF000000);
  static const muted = Color(0xFF6C6C6C);
  static const paper = Color(0xFFFFFFFF);
  static const line = Color(0xFFEAEAEA);
  static const tile = Color(0xFFF1F1F1);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.ink,
      brightness: Brightness.light,
      surface: Palette.paper,
    );
    return ThemeData(
      colorScheme: scheme.copyWith(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Palette.paper,
      fontFamily: 'Helvetica',
      fontFamilyFallback: const ['Arial', 'Roboto'],
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          height: 1.04,
          letterSpacing: -2.2,
          color: Palette.ink,
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.06,
          letterSpacing: -1.6,
          color: Palette.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: -0.9,
          color: Palette.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: -0.4,
          color: Palette.ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: Palette.ink),
        bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: Palette.ink),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Palette.paper,
        foregroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Palette.ink),
        ),
      ),
    );
  }
}
