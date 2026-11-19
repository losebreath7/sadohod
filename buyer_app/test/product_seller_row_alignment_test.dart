import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/features/product/product_screen.dart';

void main() {
  for (final modes in <List<String>>[
    ['retail'],
    ['wholesale'],
    ['wholesale', 'retail'],
  ]) {
    testWidgets('Product seller avatar, name and modes share one centre: $modes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: BuyerSellerIdentityRow(
              sellerName: 'Студия 08',
              saleModes: modes,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final avatar = find.byWidgetPredicate((w) =>
          w is SizedBox && w.width == 27 && w.height == 27);
      final name = find.text('Студия 08');
      expect(avatar, findsOneWidget);
      expect(name, findsOneWidget);
      final baseline = tester.getCenter(avatar).dy;
      expect(tester.getCenter(name).dy, closeTo(baseline, 1.5));
      for (final mode in modes) {
        expect(find.text(mode == 'retail' ? 'розница' : 'опт'), findsOneWidget);
        expect(
          tester.getCenter(find.text(mode == 'retail' ? 'розница' : 'опт')).dy,
          closeTo(baseline, 1.5),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Long seller name stays on one line without displacing badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 30),
          child: BuyerSellerIdentityRow(
            sellerName: 'Очень длинное название магазина и продавца',
            saleModes: ['wholesale', 'retail'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(
      find.text('Очень длинное название магазина и продавца'),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(find.text('опт'), findsOneWidget);
    expect(find.text('розница'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
