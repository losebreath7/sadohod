import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sadohod/features/account/favorites_screen.dart';
import 'package:sadohod/features/account/market_navigation_guide.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/features/home/home_screen.dart';

void main() {
  testWidgets('favorite heart has legible 16x15 outline without clipping',
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
      of: find.byType(FavoriteButton), matching: find.byType(FavoriteHeartGlyph));
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon), const Size(16, 15));
    expect(tester.takeException(), isNull);
  });

  test('adaptive header maintains equal gaps for phone families', () {
    for (final safeTop in [0.0, 24.0, 44.0, 62.0, 75.0]) {
      final h = BuyerHeaderLayout.forInset(safeTop);
      expect(h.contentTop - h.obstructionBottom, BuyerHeaderLayout.gap);
      expect(h.height - h.contentTop - BuyerHeaderLayout.rowHeight,
          BuyerHeaderLayout.gap);
      expect(h.height, greaterThan(h.contentTop));
    }
    final iphone = BuyerHeaderLayout.forInset(62);
    expect(iphone.obstructionBottom, 40);
    expect(iphone.contentTop, 52);
    expect(iphone.height, 92);
    expect(BuyerHeaderLayout.forInset(24).height, 76);
    expect(BuyerHeaderLayout.forInset(44).height, 84);
  });

  testWidgets('compact search is centered between island and header bottom',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 62),
            viewPadding: EdgeInsets.only(top: 62),
          ),
          child: Column(
            children: [BuyerTopBar(onBack: () {})],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final geometry = BuyerHeaderLayout.forInset(62);
    final topBar = tester.getRect(find.byType(BuyerTopBar));
    final search = tester.getRect(find.byType(SearchCapsule));
    expect(topBar.height, geometry.height);
    expect(search.height, 25);
    final topGap = search.top - geometry.obstructionBottom;
    final bottomGap = topBar.bottom - search.bottom;
    expect(topGap, greaterThan(12));
    expect(topGap, closeTo(bottomGap, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact header updates on Android, notch and island layouts',
      (tester) async {
    for (final top in <double>[0, 24, 44, 62]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(top: top),
            viewPadding: EdgeInsets.only(top: top),
          ),
          child: Column(children: [
            BuyerTopBar(onBack: () {}),
          ]),
        ),
      )));
      await tester.pumpAndSettle();
      final layout = BuyerHeaderLayout.forInset(top);
      final bounds = tester.getRect(find.byType(BuyerTopBar));
      final input = tester.getRect(find.byType(SearchCapsule));
      expect(bounds.height, closeTo(layout.height, 0.01));
      expect(input.top - layout.obstructionBottom,
          closeTo(bounds.bottom - input.bottom, 0.01));
      expect(tester.takeException(), isNull);
    }
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
  testWidgets('favorite sellers header uses the navigation chevron and returns to profile',
      (tester) async {
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation:'/account',routes:[
      GoRoute(path:'/account',builder:(_,_)=>Scaffold(body:Builder(
        builder:(context)=>Column(children:[
          TextButton(onPressed:()=>context.push('/favorite-sellers'),child:const Text('open sellers')),
          TextButton(onPressed:()=>context.push('/navigation'),child:const Text('open guide')),
        ])))),
      GoRoute(path:'/favorite-sellers',builder:(_,_)=>const Scaffold(body:FavoritesScreen(sellers:true))),
      GoRoute(path:'/navigation',builder:(_,_)=>const Scaffold(body:MarketNavigationGuideScreen())),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig:router));
    await tester.tap(find.text('open guide'));
    await tester.pumpAndSettle();
    final arrow = find.byType(SadohodBackButton);
    expect(arrow,findsOneWidget);
    final guideRect = tester.getRect(arrow);
    expect(guideRect.size,const Size(32,28));
    final glyph = find.descendant(of:arrow,matching:find.byIcon(Icons.chevron_left));
    expect(tester.widget<Icon>(glyph).size,27);
    expect(tester.widget<Icon>(glyph).color,Colors.black);
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open sellers'));
    await tester.pumpAndSettle();
    expect(arrow,findsOneWidget);
    expect(tester.getRect(arrow),guideRect);
    expect(tester.getCenter(find.text('любимые продавцы')).dx,closeTo(195,0.1));
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(find.text('open sellers'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

}
