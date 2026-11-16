import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/features/home/home_screen.dart';
import 'package:sadohod/features/product/product_screen.dart';

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

  testWidgets('one favorite on product: sale tags replace seller heart', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SellerDetails(
        id: 's03', initial: DemoCatalog.sellers[2],
        saleModes: const ['wholesale', 'retail'],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Опт'), findsOneWidget);
    expect(find.text('Розница'), findsOneWidget);
    expect(find.byTooltip('В избранное'), findsNothing);
  });

  testWidgets('home renders one pinned search header, no all products button', (tester) async {
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
    expect(find.text('Все товары'), findsNothing);
    expect(find.byTooltip('Поиск по фотографии'), findsOneWidget);
  });
}
