import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_v3.dart';

class RequestFlowApi extends SellerApi {
  RequestFlowApi({this.status = 'pending', this.existingShop = false}) {
    token = 'test';
  }
  String status;
  bool existingShop;
  String code = 'Б-2В-82';
  final writes = <String>[];
  Map<String, dynamic> get request => {
    'id': 'request-1', 'zone': 'Линия Б', 'code': code,
    'status': status, 'note': status == 'rejected' ? 'Неверный номер' : '',
  };
  @override
  Future<Map<String, dynamic>> call(String route, {
    String method = 'GET', Map<String, dynamic>? body,
  }) async {
    if (method != 'GET') {
      writes.add('$method $route');
      if (method != 'PUT') throw StateError('Must update the existing request');
      code = body!['code'] as String;
      status = 'pending';
      return request;
    }
    switch (route) {
      case '/account': return {'name': 'Продавец', 'email': 'test@example.com'};
      case '/merchant/me': return {
        'shop': existingShop || status == 'approved' ? {'id': 's1', 'name': 'Продавец'} : null,
        'applications': existingShop ? [] : [request],
      };
      case '/merchant/pavilions': return {
        'items': [
          if (existingShop) {'id': 'p0', 'zone': 'Линия Б', 'code': 'Б-2В-81', 'status': 'approved'},
          if (status == 'approved') {'id': 'p1', 'zone': 'Линия Б', 'code': code, 'status': 'approved'},
        ],
        'requests': existingShop && status != 'approved' ? [request] : [],
      };
      case '/merchant/products': return {'items': []};
    }
    throw StateError('Unexpected $route');
  }
}

void main() {
  for (final width in [390.0, 402.0]) {
    testWidgets('Pending request survives restart, camera opens without publishing ($width)', (tester) async {
      tester.view.physicalSize = Size(width, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = RequestFlowApi();
      for (var i = 0; i < 2; i++) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: SellerV3(api: api)));
        await tester.pumpAndSettle();
        expect(find.text('мои магазины'), findsOneWidget);
        expect(find.text('Б-2В-82'), findsOneWidget);
        expect(find.text('у вас пока нет магазинов'), findsNothing);
      }
      await tester.tap(find.bySemanticsLabel('Камера'));
      // The actual camera has a live preview/spinner that never settles in a
      // widget test without a physical camera. One frame is sufficient to
      // verify navigation and that no product mutation was sent.
      await tester.pump();
      expect(find.text('добавить товар'), findsOneWidget);
      expect(find.bySemanticsLabel('Снять фото'), findsOneWidget);
      expect(find.bySemanticsLabel('из галереи'), findsOneWidget);
      expect(api.writes, isEmpty);
      // Pavilion moderation is still reached through the stores tab;
      // entering the camera must not silently publish a product.
      await tester.tap(find.bySemanticsLabel('Магазины'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Б-2В-82'));
      await tester.pumpAndSettle();
      expect(find.text('магазин на проверке'), findsOneWidget);
      api.status = 'approved';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('магазин подтверждён'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final existingShop in [false, true]) {
    testWidgets('Rejected request uses same id on resubmission (existing shop: $existingShop)', (tester) async {
      tester.view.physicalSize = const Size(390, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = RequestFlowApi(status: 'rejected', existingShop: existingShop);
      await tester.pumpWidget(MaterialApp(home: SellerV3(api: api)));
      await tester.pumpAndSettle();
      if (existingShop) {
        await tester.tap(find.text('мои магазины'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Б-2В-82'));
      await tester.pumpAndSettle();
      expect(find.text('Причина: Неверный номер'), findsOneWidget);
      await tester.tap(find.text('исправить адрес'));
      await tester.pumpAndSettle();
      final number = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '82');
      await tester.enterText(number, '83');
      await tester.ensureVisible(find.text('отправить повторно'));
      await tester.tap(find.text('отправить повторно'));
      await tester.pumpAndSettle();
      expect(api.code, 'Б-2В-83');
      expect(api.writes, [existingShop
        ? 'PUT /merchant/pavilions/requests/request-1'
        : 'PUT /merchant/applications/request-1']);
      expect(find.text('магазин на проверке'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
