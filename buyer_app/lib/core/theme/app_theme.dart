import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

abstract final class Palette {
  static const ink = BuyerColors.ink;
  static const muted = BuyerColors.muted;
  static const paper = BuyerColors.paper;
  static const line = BuyerColors.line;
  static const tile = BuyerColors.tile;
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
      fontFamily: SadohodFont.family,
      fontFamilyFallback: SadohodFont.fallback,
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: SadohodFont.hero,
          fontWeight: FontWeight.w700,
          height: 1.04,
          letterSpacing: -2.2,
          color: Palette.ink,
        ),
        displayMedium: TextStyle(
          fontSize: SadohodFont.display,
          fontWeight: FontWeight.w700,
          height: 1.06,
          letterSpacing: -1.6,
          color: Palette.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: SadohodFont.heading,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: -0.9,
          color: Palette.ink,
        ),
        titleLarge: TextStyle(
          fontSize: SadohodFont.title,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: -0.4,
          color: Palette.ink,
        ),
        bodyLarge: TextStyle(fontSize: SadohodFont.body, height: 1.45, color: Palette.ink),
        bodyMedium: TextStyle(fontSize: SadohodFont.supporting, height: 1.45, color: Palette.ink),
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
          horizontal: SadohodSpace.x4,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SadohodControl.buyerFieldRadius),
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
