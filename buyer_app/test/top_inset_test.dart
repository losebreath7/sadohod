import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/features/account/favorites_screen.dart';
import 'package:sadohod/features/home/home_screen.dart';
import 'package:sadohod/core/widgets/common.dart';
import 'package:sadohod/data/catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('nested product grid never repeats iOS top safe padding',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 62),
            viewPadding: EdgeInsets.only(top: 62),
          ),
          child: SingleChildScrollView(
            child: ProductGrid(products: DemoCatalog.products.take(2).toList()),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.padding, EdgeInsets.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buyer header starts at Figma y=0 without adding a top inset',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();

    // The phone mock injects a 62 px iOS top safe area. The header itself
    // contains that space (the Figma wordmark is at y=58, search at y=275);
    // nesting another SafeArea would shift all screens down a second time.
    final scaffoldFinder = find.byWidgetPredicate(
      (widget) => widget is Scaffold && widget.bottomNavigationBar != null,
    );
    expect(scaffoldFinder, findsOneWidget);
    final shell = tester.widget<Scaffold>(scaffoldFinder);
    expect(shell.body, isA<SafeArea>());
    final contentArea = shell.body! as SafeArea;
    expect(contentArea.top, isFalse);
    expect(contentArea.bottom, isFalse);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    expect(tester.takeException(), isNull);

    appRouter.go('/favorites');
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(FavoritesScreen)).dy, 0);
    expect(tester.takeException(), isNull);

    appRouter.go('/favorite-sellers');
    await tester.pumpAndSettle();
    expect(find.text('любимые продавцы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
