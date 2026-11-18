import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Manrope is shared and app colour identities stay distinct', () {
    expect(SadohodFont.family, 'packages/sadohod_shared_core/Manrope');
    expect(SadohodThemePalette.buyer.background, BuyerColors.paper);
    expect(SadohodThemePalette.seller.background, SellerColors.background);
    expect(SadohodThemePalette.buyer.background,
        isNot(SadohodThemePalette.seller.background));
    expect(SadohodThemePalette.buyer.accent, BuyerColors.ink);
    expect(SadohodThemePalette.seller.accent, SellerColors.burgundy);
  });

  test('all seven Manrope font resources load from shared package', () async {
    const fonts = <String, int>{
      'Manrope-ExtraLight.ttf': 90000,
      'Manrope-Light.ttf': 90000,
      'Manrope-Regular.ttf': 90000,
      'Manrope-Medium.ttf': 90000,
      'Manrope-SemiBold.ttf': 90000,
      'Manrope-Bold.ttf': 90000,
      'Manrope-ExtraBold.ttf': 90000,
    };
    for (final file in fonts.entries) {
      final bytes = await rootBundle.load(
        'packages/sadohod_shared_core/assets/fonts/${file.key}',
      );
      expect(bytes.lengthInBytes, greaterThan(file.value));
    }
  });

  test('bundled Manrope family is consistent across all product text roles', () {
    for (final style in [
      BuyerProductType.catalogAddress,
      BuyerProductType.catalogTitle,
      BuyerProductType.catalogPrice,
      BuyerProductType.detailTitle,
      BuyerProductType.detailPrice,
      SellerProductType.cardTitle,
      SellerProductType.cardPrice,
    ]) {
      expect(style.fontFamily, SadohodFont.family);
      expect(style.fontFamilyFallback, SadohodFont.fallback);
    }
  });


  test('every explicit Dart font family comes from the shared Manrope token', () {
    final sourceDirs = <Directory>[
      Directory('lib'),
      Directory('../buyer_app/lib'),
      Directory('../seller_app/lib'),
      Directory('../shared/flutter_core/lib'),
    ];
    final declaration = RegExp(r'fontFamily\s*:\s*');
    for (final dir in sourceDirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in declaration.allMatches(source)) {
          final value = source.substring(match.end).trimLeft();
          expect(
            value.startsWith("'") || value.startsWith('"'),
            isFalse,
            reason: '${entity.path}: declare the shared SadohodFont.family instead of a literal font',
          );
        }
      }
    }
  });

  test('product detail applies Manrope to each locally styled text', () {
    final source = File('lib/features/product/product_screen.dart').readAsStringSync();
    final styles = RegExp(r'TextStyle\s*\(').allMatches(source).length;
    final manrope = RegExp(
      r'TextStyle\s*\(\s*fontFamily:\s*SadohodFont\.family',
    ).allMatches(source).length;
    expect(styles, greaterThan(0));
    expect(manrope, styles,
        reason: 'Product detail must not silently inherit a fallback font');
  });

  test('design spacing and durations are increasing', () {
    expect(SadohodSpace.x1, lessThan(SadohodSpace.x2));
    expect(SadohodSpace.x2, lessThan(SadohodSpace.x3));
    expect(SadohodSpace.x3, lessThan(SadohodSpace.x4));
    expect(SadohodSpace.x4, lessThan(SadohodSpace.x6));
    expect(SadohodSpace.x6, lessThan(SadohodSpace.x8));
    expect(SadohodMotion.quick, lessThan(SadohodMotion.standard));
    expect(SadohodMotion.standard, lessThan(SadohodMotion.deliberate));
  });

  test('R19 Manrope product roles are consistent across both applications', () {
    for (final style in [
      BuyerProductType.catalogAddress,
      BuyerProductType.catalogPrice,
      BuyerProductType.catalogTitle,
      BuyerProductType.detailAddress,
      BuyerProductType.detailTitle,
      BuyerProductType.detailPrice,
      BuyerProductType.secondary,
      SellerProductType.cardTitle,
      SellerProductType.cardPrice,
      SellerProductType.secondary,
    ]) {
      expect(style.fontFamily, SadohodFont.family);
      expect(style.fontFamilyFallback, SadohodFont.fallback);
      expect(style.height, greaterThanOrEqualTo(1.2));
    }
    expect(BuyerProductType.catalogAddress.fontSize, 14);
    expect(BuyerProductType.catalogPrice.fontSize, 13);
    expect(BuyerProductType.catalogTitle.fontSize, 12);
    expect(BuyerProductType.detailTitle.fontSize, 16);
    expect(BuyerProductType.detailPrice.fontSize, 16);
    expect(BuyerProductType.detailTitle.fontWeight,
        BuyerProductType.detailPrice.fontWeight);
    expect(SellerProductType.cardTitle.color, SellerColors.brown);
    expect(SellerProductType.cardPrice.color, SellerColors.brown);
    expect(BuyerProductType.detailTitle.color, BuyerColors.ink);
  });
}
