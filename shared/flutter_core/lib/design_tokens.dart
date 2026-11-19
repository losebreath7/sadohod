import 'package:flutter/material.dart';

/// Shared *rules*, deliberately not a shared colour scheme.
///
/// Buyer and seller keep independent identities. These semantic constants are
/// the starting point for gradual component migration, not an instruction to
/// replace every special-case Figma measurement at once.
abstract final class SadohodFont {
  // Flutter prefixes font families exported from package pubspec manifests.
  // Both Flutter apps use the same bundled Manrope family, including U+20BD (₽).
  static const family = 'packages/sadohod_shared_core/Manrope';
  // Do not specify an alternate application font family. Missing glyphs are
  // handled by the Flutter text engine; all bundled UI typography is Manrope.
  static const fallback = <String>[];

  static const caption = 12.0;
  static const supporting = 13.0;
  static const body = 15.0;
  static const control = 16.0;
  static const title = 20.0;
  static const heading = 27.0;
  static const display = 36.0;
  static const hero = 44.0;

  static const lineHeightTight = 1.15;
  static const lineHeightBody = 1.45;
}

/// Semantic typography. Shared geometry and Manrope, separate theme colours.
/// Use these styles for product information instead of page-local font sizes.
abstract final class BuyerProductType {
  static const catalogAddress = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: BuyerColors.ink,
  );
  static const catalogPrice = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: BuyerColors.ink,
  );
  static const catalogTitle = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: BuyerColors.muted,
  );
  static const detailAddress = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: BuyerColors.ink,
  );
  static const detailTitle = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: BuyerColors.ink,
  );
  static const detailPrice = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: BuyerColors.ink,
  );
  static const secondary = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: BuyerColors.muted,
  );
}

abstract final class SellerProductType {
  static const cardTitle = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: SellerColors.brown,
  );
  static const cardPrice = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: SellerColors.brown,
  );
  static const secondary = TextStyle(
    fontFamily: SadohodFont.family,
    fontFamilyFallback: SadohodFont.fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: SellerColors.brown,
  );
}

abstract final class SadohodSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

abstract final class SadohodRadius {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 24.0;
}

abstract final class SadohodMotion {
  static const quick = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 220);
  static const deliberate = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
  static const imageFade = standard;
}

abstract final class BuyerColors {
  static const ink = Color(0xFF000000);
  static const muted = Color(0xFF6C6C6C);
  static const paper = Color(0xFFFFFFFF);
  static const line = Color(0xFFEAEAEA);
  static const tile = Color(0xFFF1F1F1);
  static const disabled = Color(0xFF9A9A9A);
}

abstract final class SellerColors {
  static const background = Color(0xFFF0EFEB);
  static const brown = Color(0xFF48352D);
  static const burgundy = Color(0xFF5F0F10);
  static const muted = Color(0xFFA5A5A5);
  static const blue = Color(0xFFA5BCD6);
  // Existing seller warning/error colour retained for compatibility.
  static const danger = Color(0xFF670D10);
}

/// Semantic roles shared between themes; their values remain independent.
@immutable
class SadohodThemePalette {
  const SadohodThemePalette({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
  });
  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;

  static const buyer = SadohodThemePalette(
    background: BuyerColors.paper,
    primaryText: BuyerColors.ink,
    secondaryText: BuyerColors.muted,
    accent: BuyerColors.ink,
  );

  static const seller = SadohodThemePalette(
    background: SellerColors.background,
    primaryText: SellerColors.brown,
    secondaryText: SellerColors.muted,
    accent: SellerColors.burgundy,
  );
}
