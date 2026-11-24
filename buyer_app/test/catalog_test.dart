import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/data/catalog.dart';

void main() {
  test('demo product data has valid seller links', () {
    expect(DemoCatalog.products, isNotEmpty);
    for (final product in DemoCatalog.products) {
      expect(DemoCatalog.findSeller(product.sellerId), isNotNull);
      expect(product.price, greaterThan(0));
    }
  });

  test('category filters select matching products', () {
    final shoes = DemoCatalog.filtered(category: 'Обувь');
    expect(shoes, isNotEmpty);
    expect(shoes.every((p) => p.category == 'Обувь'), isTrue);
  });

  test('search by title is case insensitive', () {
    final result = DemoCatalog.filtered(query: 'КУРТКА');
    expect(result, isNotEmpty);
    expect(
      result.every((p) => p.title.toLowerCase().contains('куртка')),
      isTrue,
    );
  });

  test('ruble formatting groups thousands', () {
    expect(formatRubles(3890), '≈ 3 890 ₽');
    expect(formatRubles(990), '≈ 990 ₽');
    expect(formatRubles(0), '≈ 0 ₽');
  });
}
