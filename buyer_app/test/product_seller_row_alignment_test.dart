import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/features/product/product_screen.dart';

void main() {
  for (final width in [320.0, 390.0, 402.0]) {
    testWidgets('Seller avatar, name and both tags share one vertical center at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var openedSeller = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: BuyerSellerIdentityRow(
              name: 'Студия 08',
              saleModes: const ['wholesale', 'retail'],
              onSellerTap: () => openedSeller = true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final avatar = find.byKey(const ValueKey('buyer-seller-avatar'));
      final name = find.byKey(const ValueKey('buyer-seller-name'));
      final wholesale = find.byKey(const ValueKey('buyer-mode-wholesale'));
      final retail = find.byKey(const ValueKey('buyer-mode-retail'));

      expect(avatar, findsOneWidget);
      expect(name, findsOneWidget);
      expect(wholesale, findsOneWidget);
      expect(retail, findsOneWidget);
      final center = tester.getCenter(avatar).dy;
      for (final element in [name, wholesale, retail]) {
        expect(tester.getCenter(element).dy, closeTo(center, 1));
      }
      expect(tester.getRight(retail).dx, lessThanOrEqualTo(width - 29));
      expect(tester.takeException(), isNull);

      await tester.tap(name);
      expect(openedSeller, isTrue);
    });
  }

  testWidgets('Long seller name truncates without moving retail tag or avatar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 30),
          child: BuyerSellerIdentityRow(
            name: 'Название очень длинного магазина продавца с павильонами',
            saleModes: ['retail'],
            onSellerTap: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final name = tester.widget<Text>(
      find.byKey(const ValueKey('buyer-seller-name')),
    );
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(find.byKey(const ValueKey('buyer-mode-retail')), findsOneWidget);
    expect(find.byKey(const ValueKey('buyer-mode-wholesale')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
