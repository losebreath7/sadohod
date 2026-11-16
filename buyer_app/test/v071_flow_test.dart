import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/features/home/home_screen.dart';
import 'package:sadohod/core/widgets/common.dart';

void main() {
  test('selected offer modes are decoded from API', () {
    final product = DemoProduct.fromJson({
      'id': 'p-12', 'title': 'Test', 'category': 'Clothes',
      'image': '/a.jpg', 'colors': [],
      'offers': [{
        'sale_modes': ['wholesale', 'retail'],
        'seller': {'id': 's', 'name': 'Seller', 'pavilion': 'B-17', 'zone': '4'},
      }],
    }, 'http://example.com');
    expect(product.saleModes, ['wholesale', 'retail']);
  });

  testWidgets('product tile has one favorite and preserves offer modes', (tester) async {
    // SellerDetails was removed. Test the actual product tile and the
    // corresponding offer model without introducing a second seller heart.
    final product = DemoCatalog.products[2];
    expect(product.saleModes, containsAll(['wholesale', 'retail']));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 150, child: ProductTile(product: product))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteButton), findsOneWidget);
  });

  testWidgets('home renders one pinned search header, no all products button', (tester) async {
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
    expect(find.text('Все товары'), findsNothing);
    expect(find.text('найти по фото'), findsOneWidget);
  });
}
