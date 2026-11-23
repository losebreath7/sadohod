import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/features/product/product_screen.dart';

void main() {
  test('pavilion count uses correct Russian forms, without demo wording', () {
    for (final row in <(int, String)>[
      (1, '1 павильон'),
      (2, '2 павильона'),
      (3, '3 павильона'),
      (4, '4 павильона'),
      (5, '5 павильонов'),
      (11, '11 павильонов'),
      (12, '12 павильонов'),
      (14, '14 павильонов'),
      (21, '21 павильон'),
      (22, '22 павильона'),
      (25, '25 павильонов'),
    ]) {
      expect(pavilionCountLabel(row.$1), row.$2);
      expect(pavilionCountLabel(row.$1), isNot(contains('демонстрационные')));
    }
  });

  test('a product with two distinct verified offer records keeps both', () {
    final product = DemoProduct.fromJson({
      'id': 'p01',
      'title': 'Ковёр',
      'category': 'Товары для дома',
      'image': '',
      'description': '',
      'colors': <String>[],
      'offers': [
        {
          'seller': {
            'id': 's1', 'name': 'Магазин', 'pavilion': '2В-99',
            'zone': 'корпус А',
          },
          'pavilion': {
            'id': 'a1', 'code': '2В-99', 'zone': 'корпус А',
          },
          'sale_modes': ['retail'],
        },
        {
          'seller': {
            'id': 's1', 'name': 'Магазин', 'pavilion': '2В-99',
            'zone': 'корпус А',
          },
          'pavilion': {
            'id': 'b1', 'code': '0-00-77', 'zone': 'птичий рынок',
          },
          'sale_modes': ['retail'],
        },
      ],
    }, '');
    expect(product.availableOffers.length, 2);
    expect(product.availableOffers.map((o) => o.pavilion).toList(),
        ['2В-99', '0-00-77']);
    expect(product.availableOffers.map((o) => o.seller.zone).toList(),
        ['корпус А', 'птичий рынок']);
    expect(product.availableOffers.last.seller.pavilion, '0-00-77');
    expect(pavilionCountLabel(product.availableOffers.length), '2 павильона');
  });
}
