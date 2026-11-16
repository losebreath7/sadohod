import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_notifications.dart';
import 'package:sadohod_seller/seller_v3.dart';

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
  testWidgets('pending notification never opens a mutable product editor', (tester) async {
    final api = FakeNotificationApi();
    tester.view.physicalSize = const Size(390, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: SellerV3(api: api, initialFrame: '366:15805')));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(SellerV3));
    state.setState(() {
      state.products = <Map<String, dynamic>>[{
        'id': 'product-1', 'title': 'Товар на проверке',
        'status': 'pending', 'images': <String>[],
        'listings': <Map<String, dynamic>>[{
          'pavilion_id': 'p1', 'status': 'pending', 'price': null,
          'sale_modes': <String>['retail'],
        }],
      }];
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('уведомления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Товар не прошёл модерацию'));
    await tester.pumpAndSettle();
    expect(state.screen, 'catalog');
    expect(state.screen, isNot('editProduct'));
    expect(tester.takeException(), isNull);
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
