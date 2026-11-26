import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/sadohodets_cabinet.dart';
import 'package:sadohod_seller/courier_seller_screen.dart';

Map<String,dynamic> product(String id, String title) => {
  'id':id, 'title':title, 'price':3890, 'images': <String>[],
  'offers': <Map<String,dynamic>>[],
};

class SearchTestApi extends SellerApi {
  final queries = <String>[];
  final delayed = <String,Completer<Map<String,dynamic>>>{};
  @override
  Future<Map<String,dynamic>> call(String route,
    {String method = 'GET', Map<String,dynamic>? body}) async {
    final uri = Uri.parse(route);
    if (uri.path == '/account') return {'name':'Анна','email':'test@example.com'};
    if (uri.path == '/sadohodets/me') throw SellerApiException(404,'нет анкеты');
    if (uri.path == '/products') return {'items':[product('1','Куртка'),product('2','Ковер')]};
    if (uri.path == '/sellers/shop-1') return {'id':'shop-1','name':'losebreath','pavilion':'А-14','contact':'','products':[]};
    if (uri.path == '/sellers/shop-1/reviews') return {'items':[],'average':null};
    if (uri.path == '/search/text') {
      final query = uri.queryParameters['q']!;
      queries.add(query);
      if (delayed.containsKey(query)) return delayed[query]!.future;
      if (query == 'losebreath' || query == 'магазин') return {
        'items': query == 'магазин' ? [product('1','Куртка')] : [],
        'sellers':[{'id':'shop-1','name':'losebreath','pavilion':'А-14'}],
      };
      return {'items': query == 'ковер' ? [product('2','Ковер')] :
        query == 'брюки' ? [product('3','Брюки')] : <Map<String,dynamic>>[]};
    }
    return {'items':[]};
  }
}

void main() {
  Future<void> mount(WidgetTester tester, SearchTestApi api) async {
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SadohodetsCabinet(
      api:api,initialName:'Анна',onBack:(){},
    ))));
    await tester.pumpAndSettle();
  }

  testWidgets('typing searches without Enter; clearing returns catalogue; tags use server',
    (tester) async {
      final api = SearchTestApi();
      await mount(tester,api);
      final field = find.byType(TextField).first;
      expect(find.text('Куртка'),findsOneWidget);
      await tester.enterText(field,'к');
      await tester.pump(const Duration(milliseconds:100));
      await tester.enterText(field,'ковер');
      await tester.pump(const Duration(milliseconds:299));
      expect(api.queries,isEmpty);
      await tester.pump(const Duration(milliseconds:1));
      await tester.pumpAndSettle();
      expect(api.queries,['ковер']);
      expect(find.text('Куртка'),findsNothing);
      expect(find.text('Ковер'),findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Куртка'),findsOneWidget);
      await tester.enterText(field,'несуществующий товар');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.queries.last,'несуществующий товар');
      expect(find.text('Ничего не найдено'),findsOneWidget);
      await tester.tap(find.text('брюки').first);
      await tester.pumpAndSettle();
      expect(api.queries.last,'брюки');
      expect(find.text('Брюки'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });

  testWidgets('late results from an earlier query do not replace a newer result',
    (tester) async {
      final api = SearchTestApi();
      final old = Completer<Map<String,dynamic>>();
      api.delayed['старый'] = old;
      await mount(tester,api);
      final field = find.byType(TextField).first;
      await tester.enterText(field,'старый');
      await tester.pump(const Duration(milliseconds:300));
      await tester.pump();
      expect(api.queries,['старый']);
      await tester.enterText(field,'ковер');
      await tester.pump(const Duration(milliseconds:300));
      await tester.pumpAndSettle();
      expect(find.text('Ковер'),findsOneWidget);
      old.complete({'items':[product('old','Старый результат')]});
      await tester.pumpAndSettle();
      expect(find.text('Старый результат'),findsNothing);
      expect(find.text('Ковер'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  testWidgets('seller-only and mixed results open the public shop', (tester) async {
    final api=SearchTestApi();
    await mount(tester,api);
    final field=find.byType(TextField).first;
    await tester.enterText(field,'магазин');
    await tester.pump(const Duration(milliseconds:300));
    await tester.pumpAndSettle();
    final hit=find.byKey(const ValueKey('search-seller-shop-1'));
    expect(hit,findsOneWidget);
    expect(tester.getTopLeft(hit).dy,lessThan(tester.getTopLeft(find.text('Куртка')).dy));
    await tester.enterText(field,'losebreath');
    await tester.pump(const Duration(milliseconds:300));
    await tester.pumpAndSettle();
    expect(hit,findsOneWidget);
    expect(find.text('Куртка'),findsNothing);
    expect(find.text('Ничего не найдено'),findsNothing);
    await tester.tap(hit);
    await tester.pumpAndSettle();
    expect(find.byType(CourierSellerScreen),findsOneWidget);
    expect(find.text('losebreath'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

}
