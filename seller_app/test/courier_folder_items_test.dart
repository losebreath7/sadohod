import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
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
    final counterRight = find.byKey(const ValueKey('folder-quantity-Куртка-+'));
    final surface = find.byKey(const ValueKey('folder-item-surface-Куртка'));
    expect(tester.getTopLeft(photo).dx,15);
    expect(tester.getBottomRight(counterRight).dx,375);
    expect(tester.getRect(surface).right,375);
    expect(tester.getTopLeft(title).dx,81);
    expect(tester.getTopLeft(price).dx,81);
    await tester.drag(title,const Offset(-135,0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(photo).dx,-45);
    expect(tester.getTopLeft(title).dx,21);
    expect(tester.getTopLeft(price).dx,21);
    expect(tester.getRect(find.text('А-14')),address);
    expect(tester.getBottomRight(find.bySemanticsLabel('Удалить товар')).dx,380);
    expect(tester.getRect(surface).right,268);
    await tester.drag(find.text('Брюки'),const Offset(-135,0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dx,81);
    expect(tester.getBottomRight(counterRight).dx,375);
    expect(find.bySemanticsLabel('Удалить товар'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('long title fits with visible price at width $width scale $scale', (tester) async {
        tester.view.physicalSize = Size(width,844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final entry = item('Верхняя одежда · образец 121 — очень длинное название товара', 'А-14');
        final id = entry['product_id'];
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
          data: MediaQueryData(size: Size(width,844), textScaler: TextScaler.linear(scale)),
          child: CourierFolderItems(
            items:[entry], baseUrl:'https://example.com',
            onOpen:(_) async {}, onQuantity:(_,_) async {}, onCollected:(_) async {}, onRemove:(_) async {},
          ),
        ))));
        final photo = find.byKey(ValueKey('folder-item-photo-$id'));
        final title = find.byKey(ValueKey('folder-item-title-$id'));
        final price = find.byKey(ValueKey('folder-item-price-$id'));
        final bounds = tester.getRect(photo);
        expect(tester.getRect(price).bottom, lessThanOrEqualTo(bounds.bottom));
        expect(tester.getRect(title).bottom, lessThanOrEqualTo(tester.getRect(price).top + .01));
        expect(tester.takeException(), isNull);
        await tester.drag(title, const Offset(-130,0));
        await tester.pumpAndSettle();
        expect(tester.getRect(price).bottom, lessThanOrEqualTo(bounds.bottom));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('folder caption is compact and centered relative to the photo', (tester) async {
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final noPrice = item('Без цены','А-14');
    (noPrice['product'] as Map).remove('price');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CourierFolderItems(
      items:[item('Куртка','А-14'), item('Верхняя одежда · образец 121','А-14'), noPrice],
      baseUrl:'https://example.com', onOpen:(_) async {},
      onQuantity:(_,_) async {}, onCollected:(_) async {}, onRemove:(_) async {},
    ))));
    for (final id in ['Куртка','Верхняя одежда · образец 121']) {
      final title=find.byKey(ValueKey('folder-item-title-$id'));
      final price=find.byKey(ValueKey('folder-item-price-$id'));
      final photo=find.byKey(ValueKey('folder-item-photo-$id'));
      final titleRect=tester.getRect(title);
      final priceRect=tester.getRect(price);
      expect(priceRect.top-titleRect.bottom,closeTo(4,2));
      expect((titleRect.top+priceRect.bottom)/2,closeTo(tester.getCenter(photo).dy,1.5));
      expect(tester.widget<Text>(title).style!.fontSize,14);
      expect(tester.widget<Text>(title).style!.fontWeight,FontWeight.w500);
      expect(tester.widget<Text>(title).style!.color,SellerColors.brown);
      expect(tester.widget<Text>(price).style!.fontSize,13);
      expect(tester.widget<Text>(price).style!.fontWeight,FontWeight.w600);
    }
    final title=find.byKey(const ValueKey('folder-item-title-Без цены'));
    expect(tester.getCenter(title).dy,closeTo(tester.getCenter(
      find.byKey(const ValueKey('folder-item-photo-Без цены'))).dy,1));
    expect(find.byKey(const ValueKey('folder-item-price-Без цены')),findsNothing);
    expect(tester.takeException(),isNull);
  });

}
