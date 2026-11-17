import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/features/home/home_screen.dart';

void main() {
  testWidgets('favorite heart has legible 16x15 Figma vector without clipping',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 20,
            width: 22,
            child: FavoriteButton('test-product', small: true, alignRight: true),
          ),
        ),
      ),
    ));
    await tester.pump();
    final icon = find.descendant(
      of: find.byType(FavoriteButton), matching: find.byType(DesignIcon));
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon), const Size(16, 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact search row clears 62px Dynamic Island without extra SafeArea',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 62)),
          child: Column(
            children: [BuyerTopBar(onBack: () {})],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(buyerCompactHeaderHeight, 100);
    expect(tester.getSize(find.byType(BuyerTopBar)).height, 100);
    expect(tester.getTopLeft(find.byType(SearchCapsule)).dy,
        greaterThanOrEqualTo(66));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home wordmark is below Dynamic Island in the large header',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(SadohodWordmark), findsOneWidget);
    expect(tester.getTopLeft(find.byType(SadohodWordmark)).dy,
        greaterThanOrEqualTo(62));
    expect(tester.takeException(), isNull);
  });
}
