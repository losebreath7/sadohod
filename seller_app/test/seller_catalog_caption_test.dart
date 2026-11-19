import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/seller_catalog_caption.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  testWidgets('Seller caption matches buyer: address and price, then title',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 137,
            child: SellerCatalogCaption(
              address: 'Б-08',
              price: 2450,
              title: 'Сумка с короткими ручками',
            ),
          ),
        ),
      ),
    ));

    final address = find.byKey(const ValueKey('seller-card-address'));
    final price = find.byKey(const ValueKey('seller-card-price'));
    final title = find.byKey(const ValueKey('seller-card-title'));
    expect(find.text('Б-08'), findsOneWidget);
    expect(find.text('2 450 ₽'), findsOneWidget);
    expect(find.text('Сумка с короткими ручками'), findsOneWidget);
    expect(tester.getCenter(address).dy, closeTo(tester.getCenter(price).dy, 1));
    expect(tester.getTopLeft(title).dy,
        greaterThan(tester.getBottomLeft(address).dy));
    expect(tester.getTopLeft(price).dx,
        greaterThan(tester.getTopLeft(address).dx));

    final addressText = tester.widget<Text>(address);
    final priceText = tester.widget<Text>(price);
    final titleText = tester.widget<Text>(title);
    expect(addressText.style, BuyerProductType.catalogAddress);
    expect(priceText.style, BuyerProductType.catalogPrice);
    expect(titleText.style, BuyerProductType.catalogTitle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Optional price and empty product title are handled gracefully',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 145,
          child: SellerCatalogCaption(
            address: 'A-14',
            price: null,
            title: '',
          ),
        ),
      ),
    ));
    expect(find.text('A-14'), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-card-price')), findsNothing);
    expect(find.text('Без названия'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Long pavilion and name do not overflow narrow card',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 135,
          child: SellerCatalogCaption(
            address: 'Очень длинное название павильона и сектора',
            price: 100000000,
            title: 'Очень длинное название товара с несколькими словами',
          ),
        ),
      ),
    ));
    expect(find.text('100 000 000 ₽'), findsOneWidget);
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('seller-card-title')),
    );
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  test('Pavilion address from listing and matching fallback only', () {
    const pavilions = <Map<String, dynamic>>[
      {'id': 'p1', 'code': 'Б-08'},
      {'id': 'p2', 'code': 'А-14'},
    ];
    expect(sellerListingAddress({
      'pavilion_id': 'p2', 'pavilion': {'code': 'А-14'},
    }, pavilions), 'А-14');
    expect(sellerListingAddress({'pavilion_id': 'p1'}, pavilions), 'Б-08');
    expect(sellerListingAddress({'pavilion_id': 'not-confirmed'}, pavilions), '');
    expect(sellerListingAddress(null, pavilions), '');
    expect(SellerCatalogCaption.rubles(0), '0 ₽');
    expect(SellerCatalogCaption.rubles(3890), '3 890 ₽');
  });
}
