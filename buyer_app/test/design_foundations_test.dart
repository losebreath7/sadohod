import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  test('Helvetica is shared and app colour identities stay distinct', () {
    expect(SadohodFont.family, 'packages/sadohod_shared_core/Helvetica');
    expect(SadohodThemePalette.buyer.background, BuyerColors.paper);
    expect(SadohodThemePalette.seller.background, SellerColors.background);
    expect(SadohodThemePalette.buyer.background,
        isNot(SadohodThemePalette.seller.background));
    expect(SadohodThemePalette.buyer.accent, BuyerColors.ink);
    expect(SadohodThemePalette.seller.accent, SellerColors.burgundy);
  });

  test('bundled Helvetica family is consistent across all product text roles', () {
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

  test('design spacing and durations are increasing', () {
    expect(SadohodSpace.x1, lessThan(SadohodSpace.x2));
    expect(SadohodSpace.x2, lessThan(SadohodSpace.x3));
    expect(SadohodSpace.x3, lessThan(SadohodSpace.x4));
    expect(SadohodSpace.x4, lessThan(SadohodSpace.x6));
    expect(SadohodSpace.x6, lessThan(SadohodSpace.x8));
    expect(SadohodMotion.quick, lessThan(SadohodMotion.standard));
    expect(SadohodMotion.standard, lessThan(SadohodMotion.deliberate));
  });

  test('R19 Helvetica product roles are consistent across both applications', () {
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
