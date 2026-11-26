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
    await tester.tap(find.bySemanticsLabel('Увеличить количество').first);
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
}
