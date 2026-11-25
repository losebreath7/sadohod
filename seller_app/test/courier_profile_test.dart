import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/sadohodets_cabinet.dart';
class CourierTestApi extends SellerApi {
 @override Future<Map<String,dynamic>> call(String route,{String method='GET',Map<String,dynamic>? body}) async {
   if(route=='/account')return {'name':'Анна','email':'test@example.com'};
   if(route=='/sadohodets/me')throw SellerApiException(404,'нет анкеты');
   if(route.startsWith('/products?'))return {'items':[]};
   return {'items':[]};
 }
}
void main(){
 testWidgets('courier profile has seller menu and private account email',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SadohodetsCabinet(api:CourierTestApi(),initialName:'Анна',onBack:(){}))));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Профиль').last);await tester.pumpAndSettle();
  for(final label in ['профиль','поддержка','уведомления','настройки','навигация','сотрудничество']){expect(find.text(label),findsOneWidget);}
  await tester.tap(find.text('профиль'));await tester.pumpAndSettle();
  expect(find.text('Авито'),findsNothing);expect(find.text('сайт'),findsNothing);
  await tester.scrollUntilVisible(find.text('email'),160,scrollable:find.byType(Scrollable).first);
  expect(find.text('test@example.com'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
}
