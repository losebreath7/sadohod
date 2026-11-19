import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sadohod/features/account/market_navigation_guide.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  final router = GoRouter(initialLocation: '/navigation', routes: [
    GoRoute(path: '/navigation',
        builder: (_, _) => const MarketNavigationGuideScreen()),
    GoRoute(path: '/navigation/:zone',
        builder: (_, state) => MarketNavigationZoneScreen(
          slug: state.pathParameters['zone'] ?? '',
        )),
  ]);

  test('the guide has exactly six agreed territorial areas', () {
    expect(marketGuideZones.map((z) => z.slug), [
      'a', 'b', 'rows', 'hangar', 'fur', 'birds',
    ]);
    expect(marketGuideZones.map((z) => z.title), [
      'корпус А', 'корпус Б', 'вещевые ряды',
      'ангар', 'меха и кожа', 'птичий рынок',
    ]);
    final rows = marketGuideZones.firstWhere((z) => z.slug == 'rows');
    expect(rows.description, contains('СТ'));
    expect(rows.description, contains('поперечные'));
    final hangar = marketGuideZones.firstWhere((z) => z.slug == 'hangar');
    expect(hangar.description, contains('между корпусами А и Б'));
    expect(MarketNavigationGuideScreen.mapUrl,
        'https://yandex.ru/maps/-/CXWFfZLK');
  });

  testWidgets('navigation index opens the zone guide', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Как устроены адреса павильонов на «Садоводе»'),
        findsOneWidget);
    expect(find.text('ангар'), findsOneWidget);
    await tester.ensureVisible(find.byKey(
        const ValueKey('market-guide-rows')));
    await tester.tap(find.byKey(const ValueKey('market-guide-rows')));
    await tester.pumpAndSettle();
    expect(find.text('Что это?'), findsOneWidget);
    expect(find.text('СТ7-166'), findsOneWidget);
    expect(find.text('открыть карты'), findsOneWidget);
    expect(tester.widget<Text>(find.text('вещевые ряды').first)
        .style?.fontFamily, SadohodFont.family);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown zone does not fabricate a location', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MarketNavigationZoneScreen(slug: 'unrecognized'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Раздел не найден'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
