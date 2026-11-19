import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/features/product/product_screen.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  Future<void> showAddress(WidgetTester tester, String address, {String zone = ''}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 260,
            height: 65,
            child: Align(
              alignment: Alignment.centerLeft,
              child: BuyerProductNavigationAddress(address: address, zone: zone),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('standard address shows sector and line in two aligned columns',
      (tester) async {
    await showAddress(tester, 'А-14');
    expect(find.byKey(const ValueKey('buyer-navigation-address-grid')), findsOneWidget);
    final sector = find.text('А');
    final line = find.text('14');
    final sectorLabel = find.text('- сектор');
    final lineLabel = find.text('- линия');
    expect(sector, findsOneWidget);
    expect(line, findsOneWidget);
    expect(sectorLabel, findsOneWidget);
    expect(lineLabel, findsOneWidget);

    // Values are aligned by their center, descriptions by their leading edge.
    expect((tester.getCenter(sector).dx - tester.getCenter(line).dx).abs(), lessThan(0.5));
    expect((tester.getTopLeft(sectorLabel).dx - tester.getTopLeft(lineLabel).dx).abs(), lessThan(0.5));
    expect((tester.getCenter(sector).dy - tester.getCenter(sectorLabel).dy).abs(), lessThan(0.5));
    expect((tester.getCenter(line).dy - tester.getCenter(lineLabel).dy).abs(), lessThan(0.5));
    expect(tester.takeException(), isNull);

    final style = tester.widget<Text>(sector).style!;
    expect(style.fontFamily, SadohodFont.family);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.fontSize, 12);
  });

  testWidgets('long line value retains centered value column', (tester) async {
    await showAddress(tester, 'Б-125');
    expect(find.text('Б'), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    expect((tester.getCenter(find.text('Б')).dx -
      tester.getCenter(find.text('125')).dx).abs(), lessThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown address does not invent sector or line', (tester) async {
    await showAddress(tester, 'Б-2В-81', zone: 'корпус Б');
    expect(find.byKey(const ValueKey('buyer-address-fallback')), findsOneWidget);
    expect(find.text('Б-2В-81'), findsOneWidget);
    expect(find.text('корпус Б'), findsOneWidget);
    expect(find.text('- сектор'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
