import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  test('Helvetica is shared and app colour identities stay distinct', () {
    expect(SadohodFont.family, 'Helvetica');
    expect(SadohodThemePalette.buyer.background, BuyerColors.paper);
    expect(SadohodThemePalette.seller.background, SellerColors.background);
    expect(SadohodThemePalette.buyer.background,
        isNot(SadohodThemePalette.seller.background));
    expect(SadohodThemePalette.buyer.accent, BuyerColors.ink);
    expect(SadohodThemePalette.seller.accent, SellerColors.burgundy);
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
}
