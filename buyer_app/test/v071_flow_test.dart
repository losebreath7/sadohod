import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/app/app.dart';
import 'package:sadohod/core/widgets/design.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/features/home/home_screen.dart';
import 'package:sadohod/core/widgets/common.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';

void main() {
  test('selected offer modes are decoded from API', () {
    final product = DemoProduct.fromJson({
      'id': 'p-12', 'title': 'Test', 'category': 'Clothes',
      'image': '/a.jpg', 'colors': [],
      'offers': [{
        'sale_modes': ['wholesale', 'retail'],
        'seller': {'id': 's', 'name': 'Seller', 'pavilion': 'B-17', 'zone': '4'},
      }],
    }, 'http://example.com');
    expect(product.saleModes, ['wholesale', 'retail']);
  });

  testWidgets('product tile has one favorite and preserves offer modes', (tester) async {
    // SellerDetails was removed. Test the actual product tile and the
    // corresponding offer model without introducing a second seller heart.
    final product = DemoCatalog.products[2];
    expect(product.saleModes, containsAll(['wholesale', 'retail']));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 150, child: ProductTile(product: product))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteButton), findsOneWidget);
  });

  testWidgets('home renders one pinned search header, no all products button', (tester) async {
    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
    expect(find.text('Все товары'), findsNothing);
    expect(find.text('найти по фото'), findsOneWidget);
  });
  testWidgets('home wordmark is present and mouse drags tag rail', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SadohodApp());
    appRouter.go('/home');
    await tester.pumpAndSettle();

    expect(
      find.byType(SadohodWordmark),
      findsOneWidget,
    );

    final tags = find.byType(ListView);
    expect(tags, findsOneWidget);
    expect(tester.widget<ListView>(tags).scrollDirection, Axis.horizontal);
    final horizontal = find.descendant(
      of: tags,
      matching: find.byType(Scrollable),
    );
    // The main scrollable is the first descendant. The tag rail is also
    // nested under CustomScrollView, so the unfiltered finder is ambiguous.
    final vertical = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    ).first;
    final initialVertical = tester.state<ScrollableState>(vertical).position.pixels;
    final railPosition = tester.state<ScrollableState>(horizontal).position;
    expect(railPosition.maxScrollExtent, greaterThan(0));
    expect(
      ScrollConfiguration.of(tester.element(horizontal)).dragDevices,
      contains(PointerDeviceKind.mouse),
    );

    // Test the actual viewport, not an InkWell text child. This also
    // synthesizes the complete pressed-button mouse gesture.
    await tester.drag(tags, const Offset(-140, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(horizontal).position.pixels, greaterThan(0));
    expect(tester.state<ScrollableState>(vertical).position.pixels, initialVertical);
    expect(tester.takeException(), isNull);
  });

  test('chat delivery updates without a new message ID', () {
    final pending = <Map<String, dynamic>>[
      {'id': 'one', 'delivered': false, 'staff': false},
    ];
    final delivered = <Map<String, dynamic>>[
      {'id': 'one', 'delivered': true, 'staff': false},
    ];
    expect(sadohodChatMessagesChanged(pending, pending), isFalse);
    expect(sadohodChatMessagesChanged(pending, delivered), isTrue);
    expect(sadohodChatMessagesChanged(delivered, delivered), isFalse);
  });
}
