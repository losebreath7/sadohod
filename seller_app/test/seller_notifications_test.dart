import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_notifications.dart';

class FakeNotificationApi extends SellerApi {
  FakeNotificationApi() { token = 'test-only-session'; }

  final called = <String>[];
  final data = <Map<String, dynamic>>[
    {
      'id':'event-1', 'event_type':'product','target_id':'product-1',
      'title':'Не прошло модерацию',
      'message':'Товар «Куртка» не прошёл модерацию.',
      'note':'Поменяйте фотографию','created_at':1731769200,
      'read':false,
    },
    {
      'id':'event-2', 'event_type':'pavilion','target_id':'pavilion-1',
      'title':'Проверка пройдена',
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
  testWidgets('seller moderation inbox shows reasons and navigates to product',
      (tester) async {
    final api = FakeNotificationApi();
    String? product;
    var pavilionVisits = 0;
    var backVisits = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(
        api:api, onBack:()=>backVisits++,
        onOpenPavilions:()=>pavilionVisits++,
        onOpenProduct:(id)=>product=id,
      ))));
    await tester.pumpAndSettle();

    expect(find.text('уведомления'), findsOneWidget);
    expect(find.text('НОВЫЕ'), findsOneWidget);
    expect(find.text('ПРОЧИТАННЫЕ'), findsOneWidget);
    expect(find.text('Причина: Поменяйте фотографию'), findsOneWidget);
    await tester.tap(find.text('Не прошло модерацию'));
    await tester.pumpAndSettle();
    expect(product, 'product-1');
    expect(api.called, contains('PUT /merchant/notifications/event-1/read'));

    await tester.tap(find.text('Проверка пройдена'));
    await tester.pumpAndSettle();
    expect(pavilionVisits, 1);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(backVisits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty notification feed has helpful placeholder', (tester) async {
    final api = FakeNotificationApi();
    api.data.clear();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SellerNotificationsPage(api:api, onBack:(){},
        onOpenPavilions:(){},onOpenProduct:(_){},
      ))));
    await tester.pumpAndSettle();
    expect(find.text('пока нет уведомлений'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
