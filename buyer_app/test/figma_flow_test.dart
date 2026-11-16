import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/data/account.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/core/widgets/common.dart';
import 'package:sadohod/features/account/account_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountStore.instance.products.clear();
    AccountStore.instance.sellers.clear();
    AccountStore.instance.token = null;
  });
  test('guest favourite survives reopening local store', () async {
    await AccountStore.instance.toggle('p01');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('guest.products'), ['p01']);
    await AccountStore.instance.toggle('p01');
    expect(prefs.getStringList('guest.products'), isEmpty);
  });
  test('product maps actual gallery and pavilion from API', () {
    final p = DemoProduct.fromJson({
      'id': 'p',
      'title': 'Hidden title',
      'category': 'Обувь',
      'image': '/a.jpg',
      'images': ['/a.jpg', '/b.jpg'],
      'offers': [
        {
          'seller': {
            'id': 's',
            'name': 'Shop',
            'zone': 'line B',
            'pavilion': 'Б-2В-81',
          },
        },
      ],
    }, 'https://example.com');
    expect(p.pavilion, 'Б-2В-81');
    expect(p.photos, [
      'https://example.com/a.jpg',
      'https://example.com/b.jpg',
    ]);
  });
  testWidgets('tile hides title and price, heart saves item', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            child: ProductTile(product: DemoCatalog.products.first),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(DemoCatalog.products.first.title), findsNothing);
    expect(
      find.text(formatRubles(DemoCatalog.products.first.price)),
      findsNothing,
    );
    await tester.tap(find.byTooltip('В избранное'));
    await tester.pumpAndSettle();
    expect(AccountStore.instance.products, contains('p01'));
  });
  testWidgets('email validates locally without sending request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AccountScreen())),
    );
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('получить код'));
    await tester.pump();
    expect(find.text('Проверьте адрес электронной почты'), findsOneWidget);
  });
  testWidgets('home, favorites and account fit narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SadohodApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    appRouter.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('личный кабинет'), findsOneWidget);
    expect(tester.takeException(), isNull);
    appRouter.go('/favorites');
    await tester.pumpAndSettle();
    expect(find.text('избранное'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('product push keeps navigation and back returns to catalogue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/catalog');
    await tester.pumpAndSettle();
    appRouter.push('/product/p01');
    await tester.pumpAndSettle();
    final nav = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Личный кабинет',
    );
    expect(nav, findsOneWidget);
    expect(tester.getRect(nav).bottom, lessThanOrEqualTo(700));
    expect(tester.takeException(), isNull);
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
