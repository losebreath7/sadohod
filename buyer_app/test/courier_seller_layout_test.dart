import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/public_seller_body.dart';

void main() {
  testWidgets('courier profile reuses seller layout without shop fields',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PublicSellerBody(
          name: 'Курьер',
          addresses: [],
          contacts: Text('Telegram: @courier'),
          subtitle: Text('★ 4.8 · Сегодня'),
          reviews: Text('Отзывы'),
          products: SizedBox.shrink(),
        ),
      ),
    ));

    expect(find.text('Курьер'), findsOneWidget);
    expect(find.text('★ 4.8 · Сегодня'), findsOneWidget);
    expect(find.text('Telegram: @courier'), findsOneWidget);
    expect(find.text('Отзывы'), findsOneWidget);
    expect(find.text('Павильоны'), findsNothing);
    expect(find.text('Товары'), findsNothing);
  });
}
