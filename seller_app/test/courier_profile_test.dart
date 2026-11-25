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
 testWidgets('Folder list has no title bar and starts below the safe area', (tester) async {
   tester.view.physicalSize=const Size(390,844);
   tester.view.devicePixelRatio=1;
   addTearDown(tester.view.resetPhysicalSize);
   addTearDown(tester.view.resetDevicePixelRatio);
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:MediaQuery(
     data:const MediaQueryData(size:Size(390,844),padding:EdgeInsets.only(top:62)),
     child:SadohodetsCabinet(api:CourierTestApi(),initialName:'Анна',onBack:(){}),
   ))));
   await tester.pumpAndSettle();
   await tester.tap(find.bySemanticsLabel('Папки').last);
   await tester.pumpAndSettle();
   expect(find.text('папки'),findsNothing);
   expect(find.text('Создать папку'),findsOneWidget);
   expect(tester.getTopLeft(find.text('Создать папку')).dy,lessThan(125));
   expect(tester.takeException(),isNull);
 });

 testWidgets('Open folder header extends to screen top and owns notch inset', (tester) async {
   tester.view.physicalSize = const Size(390,844);
   tester.view.devicePixelRatio = 1;
   addTearDown(tester.view.resetPhysicalSize);
   addTearDown(tester.view.resetDevicePixelRatio);
   var back = false;
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:MediaQuery(
     data:const MediaQueryData(size:Size(390,844),padding:EdgeInsets.only(top:62),viewPadding:EdgeInsets.only(top:62)),
     child:Align(alignment:Alignment.topCenter, child:CourierFolderHeader(title:'маша',onBack:(){back=true;})),
   ))));
   final header = find.byKey(const ValueKey('courier-folder-header'));
   expect(tester.getRect(header), const Rect.fromLTWH(0,0,390,92));
   final decoration = tester.widget<Container>(header).decoration as BoxDecoration;
   expect(decoration.color, Colors.white);
   expect(tester.getCenter(find.text('маша')).dx, 195);
   expect(tester.getCenter(find.text('маша')).dy, 66);
   await tester.tap(find.bySemanticsLabel('Назад'));
   expect(back,isTrue);
   expect(tester.takeException(),isNull);
 });

}
