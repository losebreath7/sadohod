import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_v3.dart';

class StartupApi extends SellerApi {
  StartupApi({
    this.hasShop = false,
    this.hasPavilion = false,
    this.hasProduct = false,
    this.pending = false,
    this.profileName = 'Продавец',
  }) {
    token = 'test-token';
  }
  final bool hasShop, hasPavilion, hasProduct, pending;
  final String profileName;
  final routes = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    routes.add(route);
    return switch (route) {
      '/account' => {'name': profileName, 'email': 'test@example.com'},
      '/merchant/me' => {
        'shop': hasShop ? {'id': 's1', 'name': profileName} : null,
        'applications': pending
            ? [
                {'id': 'r1', 'code': 'Б-2В-86', 'status': 'pending'},
              ]
            : [],
      },
      '/merchant/pavilions' => {
        'items': hasPavilion
            ? [
                {'id': 'p1', 'code': 'Б-2В-81', 'status': 'approved'},
              ]
            : [],
        'requests': [],
      },
      '/merchant/products' => {
        'items': hasProduct
            ? [
                {
                  'id': 't1',
                  'title': 'Тестовый товар',
                  'status': 'approved',
                  'images': [],
                  'listings': [
                    {
                      'pavilion_id': 'p1',
                      'status': 'approved',
                      'published': true,
                      'price': 300,
                    },
                  ],
                },
              ]
            : [],
      },
      _ => throw StateError('Unexpected route $route'),
    };
  }
}

void main() {
  assert(!const bool.fromEnvironment('FIGMA_PREVIEW'));
  final cases = <String, (StartupApi, String)>{
    'no merchant': (StartupApi(), 'у вас пока нет магазинов'),
    'merchant without pavilions': (
      StartupApi(hasShop: true),
      'у вас пока нет магазинов',
    ),
    'pending first application': (StartupApi(pending: true), 'мои магазины'),
    'approved pavilion without products': (
      StartupApi(hasShop: true, hasPavilion: true),
      'товаров пока нет',
    ),
    'approved pavilion with product': (
      StartupApi(hasShop: true, hasPavilion: true, hasProduct: true),
      'Тестовый товар',
    ),
    'missing profile name': (
      StartupApi(profileName: ''),
      'как к вам обращаться?',
    ),
  };
  for (final entry in cases.entries) {
    testWidgets('API startup: ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: SellerV3(api: entry.value.$1)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(entry.value.$1.routes, containsAll(['/account', '/merchant/me']));
      if (entry.value.$1.hasShop) {
        expect(
          entry.value.$1.routes,
          containsAll(['/merchant/pavilions', '/merchant/products']),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
