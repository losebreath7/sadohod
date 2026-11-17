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
    expect(buyerCompactHeaderHeight, 75);
    expect(tester.getSize(find.byType(BuyerTopBar)).height, 75);
    expect(tester.getTopLeft(find.byType(SearchCapsule)).dy,
        greaterThanOrEqualTo(39));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home Figma logo starts at y=58 with 16px gap to intro',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();
    final logo = find.byType(SadohodWordmark);
    expect(logo, findsOneWidget);
    expect(tester.getTopLeft(logo).dy, closeTo(58.0, 0.1));
    expect(tester.getSize(logo), const Size(98, 13));
    final subtitle = find.text('находи и забирай   //   без посредников');
    expect(subtitle, findsOneWidget);
    expect(
      tester.getTopLeft(subtitle).dy - tester.getBottomLeft(logo).dy,
      closeTo(16.0, 0.1),
    );
    expect(tester.takeException(), isNull);
  });
}
