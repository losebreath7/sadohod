import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/courier_folder_items.dart';

Map item(String id, String address, {String? pavilion, int quantity = 1}) => {
  'product_id': id, 'quantity': quantity, 'collected': false,
  'product': {'title': id, 'price': 3890, 'images': [],
    'offers': [{'pavilion': {'id': pavilion ?? address, 'code': address}}]},
};

void main() {
  test('pavilions group once even when items are not consecutive', () {
    final groups = groupCourierItems([item('one','А-14'),item('two','Б-08'),item('three','А-14')]);
    expect(groups.map((g)=>g.address), ['А-14','Б-08']);
    expect(groups.first.items.map((i)=>i['product_id']), ['one','three']);
    expect(groupCourierItems([item('one','А-14',pavilion:'a'),item('two','А-14',pavilion:'b')]).length,2);
  });
  testWidgets('folder row layout and swipe controls work independently', (tester) async {
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int quantity = 0;
    String? opened, collected, removed;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Padding(
      padding:const EdgeInsets.all(30),
      child:CourierFolderItems(
        items:[item('Куртка','А-14'),item('Брюки','А-14'),item('Сумка','Б-08')],
        baseUrl:'https://example.com',
        onOpen:(i)async{opened=i['product_id'].toString();},
        onQuantity:(i,n)async{quantity=n;},
        onCollected:(i)async{collected=i['product_id'].toString();},
        onRemove:(i)async{removed=i['product_id'].toString();},
      ),
    ))));
    expect(find.text('А-14'), findsOneWidget);
    expect(find.text('Б-08'), findsOneWidget);
    expect(find.text('≈ 3 890 ₽'), findsNWidgets(3));
    final address = tester.getRect(find.text('А-14'));
    await tester.tap(find.byKey(const ValueKey('folder-quantity-Куртка-+')));
    expect(quantity,2);
    expect(opened,isNull);
    await tester.tap(find.text('Куртка'));
    expect(opened,'Куртка');
    await tester.drag(find.text('Куртка'),const Offset(-135,0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('А-14')),address);
    await tester.tap(find.bySemanticsLabel('Собрано'));
    await tester.pumpAndSettle();
    expect(collected,'Куртка');
    await tester.drag(find.text('Брюки'),const Offset(-135,0));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Удалить товар'));
    await tester.pumpAndSettle();
    expect(removed,'Брюки');
    expect(tester.takeException(),isNull);
  });
  testWidgets('collected products move behind pending products in their pavilion and fade to exactly 50 percent', (tester) async {
    final items = [item('Куртка','А-14'), item('Брюки','А-14'), item('Сумка','Б-08')];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Padding(
      padding:const EdgeInsets.all(30),
      child:StatefulBuilder(builder:(context,setState)=>CourierFolderItems(
        items:items, baseUrl:'https://example.com',
        onOpen:(_) async {},
        onQuantity:(_,_) async {},
        onRemove:(_) async {},
        onCollected:(entry) async {
          setState(()=>entry['collected'] = entry['collected'] != true);
        },
      )),
    ))));
    final opacity = find.byKey(const ValueKey('folder-item-opacity-Куртка'));
    expect(tester.widget<AnimatedOpacity>(opacity).opacity,1.0);
    expect(tester.getTopLeft(find.text('Куртка')).dy,lessThan(tester.getTopLeft(find.text('Брюки')).dy));
    await tester.drag(find.text('Куртка'),const Offset(-135,0));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Собрано'));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity,0.5);
    expect(tester.getTopLeft(find.text('Куртка')).dy,greaterThan(tester.getTopLeft(find.text('Брюки')).dy));
    expect(tester.getTopLeft(find.text('Куртка')).dy,lessThan(tester.getTopLeft(find.text('Б-08')).dy));
    expect(find.text('А-14'),findsOneWidget);
    await tester.drag(find.text('Куртка'),const Offset(-135,0));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Снять отметку'));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity,1.0);
    expect(tester.getTopLeft(find.text('Куртка')).dy,lessThan(tester.getTopLeft(find.text('Брюки')).dy));
    expect(tester.takeException(),isNull);
  });

  testWidgets('Figma full-bleed swipe keeps title and price readable at the screen edge', (tester) async {
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CourierFolderItems(
      items:[item('Куртка','А-14'),item('Брюки','А-14')], baseUrl:'https://example.com',
      onOpen:(_) async {}, onQuantity:(_,_) async {}, onCollected:(_) async {}, onRemove:(_) async {},
    ))));
    final title = find.byKey(const ValueKey('folder-item-title-Куртка'));
    final price = find.byKey(const ValueKey('folder-item-price-Куртка'));
    final photo = find.byKey(const ValueKey('folder-item-photo-Куртка'));
    final address = tester.getRect(find.text('А-14'));
    expect(tester.getTopLeft(photo).dx,15);
    expect(tester.getTopLeft(title).dx,81);
    expect(tester.getTopLeft(price).dx,81);
    await tester.drag(title,const Offset(-135,0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(photo).dx,-45);
    expect(tester.getTopLeft(title).dx,21);
    expect(tester.getTopLeft(price).dx,21);
    expect(tester.getRect(find.text('А-14')),address);
    expect(tester.getBottomRight(find.bySemanticsLabel('Удалить товар')).dx,380);
    await tester.drag(find.text('Брюки'),const Offset(-135,0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dx,81);
    expect(find.bySemanticsLabel('Удалить товар'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

}
