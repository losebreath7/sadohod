import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/product_share_actions.dart';

void main() {
  testWidgets('Detail actions use reference spacing and optical icon alignment', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 330, child: Column(children: [
        const SizedBox(key: ValueKey('address'), height: 65),
        ProductDetailActions(productId: 'test', report: TextButton(
          onPressed: () {}, child: const Text('пожаловаться на товар'),
        )),
      ])),
    ))));
    final address = find.byKey(const ValueKey('address'));
    final actions = find.byType(ProductShareActions);
    final report = find.widgetWithText(TextButton, 'пожаловаться на товар');
    expect(tester.getTopLeft(actions).dy - tester.getBottomLeft(address).dy, 36);
    expect(tester.getTopLeft(report).dy - tester.getBottomLeft(actions).dy, 20);
    final shareIcon = find.byIcon(Icons.ios_share);
    final copyIcon = find.byIcon(Icons.link);
    expect(tester.widget<Icon>(shareIcon).size, tester.widget<Icon>(copyIcon).size);
    final shareLabel = find.text('поделиться');
    final copyLabel = find.text('скопировать');
    expect(tester.getBottomLeft(shareIcon).dy, closeTo(tester.getBottomLeft(shareLabel).dy - 2, 0.1));
    expect(tester.getBottomLeft(copyIcon).dy, closeTo(tester.getBottomLeft(copyLabel).dy, 0.1));
    expect(tester.takeException(), isNull);
  });
}
