import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  test('product navigation address uses the original Manrope SemiBold face', () {
    const style = BuyerProductType.detailNavigation;
    expect(style.fontFamily, 'packages/sadohod_shared_core/Manrope');
    expect(style.fontFamilyFallback, isEmpty);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.fontSize, 12);
    expect(style.height, 1.25);
    expect(style.color, const Color(0xff6c6c6c));

    // Other secondary labels must remain Regular; only address navigation changes.
    expect(BuyerProductType.secondary.fontWeight, FontWeight.w400);
  });
}
