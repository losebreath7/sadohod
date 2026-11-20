import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_notifications.dart';
import 'package:sadohod_seller/seller_v3.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

class FakeNotificationApi extends SellerApi {
  FakeNotificationApi() { token = 'test-only-session'; }

  final called = <String>[];
  final data = <Map<String, dynamic>>[
    {
      'id':'event-1', 'event_type':'product','target_id':'product-1',
      'title':'Товар не прошёл модерацию', 'status':'rejected',
      'message':'Товар «Куртка» не прошёл модерацию.',
      'note':'Поменяйте фотографию','created_at':1731769200,
      'read':false,
    },
    {
      'id':'event-2', 'event_type':'pavilion','target_id':'pavilion-1',
      'title':'Павильон подтверждён', 'status':'approved',
      'message':'Павильон «Б-2В-82» прошёл модерацию.',
      'note':'','created_at':1731769100, 'read':true,
    },
  ];

  @override
  Future<Map<String, dynamic>> call(String route,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    called.add('$method $route');
    if (route.endsWith('/read')) {
      data.firstWhere((item) => route.contains(item['id'] as String))['read'] = true;
      return {'read':true};
    }
    return {'items': data.map((item) => Map<String, dynamic>.of(item)).toList(),
      'unread':data.where((item) => item['read'] != true).length};
  }
}

void main() {
  test('semantic notification circles follow existing seller palette', () {
    expect(sellerNotificationTone('approved'), SellerColors.blue);
    expect(sellerNotificationTone('pending'), SellerColors.blue);
    expect(sellerNotificationTone('rejected'), SellerColors.danger);
    expect(sellerNotificationTone('removed'), SellerColors.danger);
    expect(sellerNotificationTone('unknown'), SellerColors.blue);
  });

  testWidgets('approved and rejected notifications use colored circles',
      (tester) async {
    final api = FakeNotificationApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(api: api, onOpenPavilions: () {},
        onOpenProduct: (_) {}))));
    await tester.pumpAndSettle();
    final circles = tester.widgetList<CircleAvatar>(
      find.byType(CircleAvatar)).toList();
    expect(circles.length, 2);
    expect(circles[0].backgroundColor, SellerColors.danger);
    expect(circles[1].backgroundColor, SellerColors.blue);
  });

  testWidgets('seller moderation inbox shows reasons and navigates to product',
      (tester) async {
    final api = FakeNotificationApi();
    String? product;
    var pavilionVisits = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(
        api:api,
        onOpenPavilions:()=>pavilionVisits++,
        onOpenProduct:(id)=>product=id,
      ))));
    await tester.pumpAndSettle();

    expect(find.text('НОВЫЕ'), findsOneWidget);
    expect(find.text('ПРОЧИТАННЫЕ'), findsOneWidget);
    expect(find.text('Причина: Поменяйте фотографию'), findsOneWidget);
    await tester.tap(find.text('Товар не прошёл модерацию'));
    await tester.pumpAndSettle();
    expect(product, 'product-1');
    expect(api.called, contains('PUT /merchant/notifications/event-1/read'));

    await tester.tap(find.text('Павильон подтверждён'));
    await tester.pumpAndSettle();
    expect(pavilionVisits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moderator takedown notification links to affected product',
      (tester) async {
    final api = FakeNotificationApi();
    api.data
      ..clear()
      ..add({
        'id': 'hold-1',
        'event_type': 'product_safety',
        'target_id': 'product-held',
        'title': 'Товар снят с публикации',
        'status': 'removed',
        'message': 'Товар «Кукла» снят с публикации модератором.',
        'note': 'Запрещённый контент',
        'created_at': 1731769200,
        'read': false,
      });
    String? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(
        api: api, onOpenPavilions: () {},
        onOpenProduct: (id) => opened = id,
      ))));
    await tester.pumpAndSettle();
    expect(find.text('Причина: Запрещённый контент'), findsOneWidget);
    await tester.tap(find.text('Товар снят с публикации'));
    await tester.pumpAndSettle();
    expect(opened, 'product-held');
    expect(api.called, contains('PUT /merchant/notifications/hold-1/read'));
  });

  testWidgets('profile opens notifications inside existing seller navigation', (tester) async {
    final api = FakeNotificationApi();
    tester.view.physicalSize = const Size(390, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: SellerV3(api: api, initialFrame: '366:15805')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('уведомления'));
    await tester.pumpAndSettle();
    expect(find.text('НОВЫЕ'), findsOneWidget);
    expect(find.text('Причина: Поменяйте фотографию'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('поддержка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty notification feed has helpful placeholder', (tester) async {
    final api = FakeNotificationApi();
    api.data.clear();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(api:api,
        onOpenPavilions:(){},onOpenProduct:(_){},
      ))));
    await tester.pumpAndSettle();
    expect(find.text('пока нет уведомлений'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
