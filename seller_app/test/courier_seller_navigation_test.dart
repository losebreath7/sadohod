import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/courier_product_screen.dart';
import 'package:sadohod_seller/courier_seller_screen.dart';

final seller = <String,dynamic>{
  'id':'seller-1','name':'Контур 01','pavilion':'А-14','zone':'','contact':'',
};
final product = <String,dynamic>{
  'id':'product-1','title':'Куртка','price':3890,'images':<String>[],
  'offers':[{'seller':seller,'pavilion':{'code':'А-14','zone':''},'price':3890}],
};
class SellerNavigationApi extends SellerApi {
  final calls=<String>[];
  bool rated = false;
  @override
  Future<Map<String,dynamic>> call(String route,{String method='GET',Map<String,dynamic>? body}) async {
    calls.add(route);
    if(route=='/products/product-1') return product;
    if(route=='/sellers/seller-1') return {...seller,'products':[product],'pavilions':[{'code':'А-14'}]};
    if(route=='/sellers/seller-1/reviews') return rated ? {'average':4.5,'items':[{'name':'Покупатель','rating':4,'text':'Хорошо'}]} : {'average':null,'items':[]};
    throw StateError('Unexpected route $route');
  }
}
void main(){
  testWidgets('courier opens the real seller catalogue from product and saves a product', (tester) async {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api=SellerNavigationApi();
    String? added;
    await tester.pumpWidget(MaterialApp(home:CourierProductScreen(
      api:api,initial:product,onFolder:()async{},onAddProduct:(id)async{added=id;},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('buyer-seller-name')));
    await tester.pumpAndSettle();
    expect(find.byType(CourierSellerScreen),findsOneWidget);
    expect(api.calls,contains('/sellers/seller-1'));
    expect(api.calls,contains('/sellers/seller-1/reviews'));
    expect(find.text('Контур 01'),findsOneWidget);
    expect(find.text('нет отзывов'),findsOneWidget);
    await tester.tap(find.bySemanticsLabel('В папку клиента'));
    await tester.pumpAndSettle();
    expect(added,'product-1');
    await tester.tap(find.text('Куртка'));
    await tester.pumpAndSettle();
    expect(find.byType(CourierProductScreen),findsOneWidget);
    expect(find.text('Контур 01'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('read-only seller reviews keep the same eight pixel gap', (tester) async {
    final api=SellerNavigationApi()..rated=true;
    await tester.pumpWidget(MaterialApp(home:CourierSellerScreen(api:api,sellerId:'seller-1')));
    await tester.pumpAndSettle();
    final strip=find.byKey(const ValueKey('courier-seller-reviews-list'));
    expect(tester.getRect(strip).top-tester.getRect(find.text('4.5')).bottom,closeTo(8,.1));
    expect(tester.takeException(),isNull);
  });

}
