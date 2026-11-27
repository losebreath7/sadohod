import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/data/account.dart';
import 'package:sadohod/data/api.dart';
import 'package:sadohod/data/catalog.dart';
import 'package:sadohod/features/home/home_screen.dart';

DemoProduct item(int i) => DemoProduct(
  id:'feed-$i', title:'Товар $i', category:'Одежда',
  price:1000+i,sellerId:'s01',image:'assets/products/p01.jpg',
  description:'',colors:const [],
);

void main() {
  testWidgets('home loads one page and appends next without duplicate cards', (tester) async {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account=AccountStore.instance;
    account.token=null;
    account.products.clear();
    final calls=<String?>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:HomeScreen(
      feedLoader:({String? token,String? cursor,required String category}) async {
        expect(category,'Все');
        calls.add(cursor);
        if(cursor==null) return FeedPage(List.generate(20,item),'next');
        return FeedPage([item(19),...List.generate(5,(i)=>item(i+20))],null);
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls,[null]);
    expect(find.byKey(const ValueKey('feed-product-feed-0')),findsOneWidget);
    expect(tester.widget<SliverGrid>(find.byType(SliverGrid)).delegate.estimatedChildCount,20);
    final scroll=tester.widget<CustomScrollView>(find.byKey(const PageStorageKey('buyer-home-feed'))).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent-100);
    await tester.pumpAndSettle();
    expect(calls,[null,'next']);
    expect(tester.widget<SliverGrid>(find.byType(SliverGrid)).delegate.estimatedChildCount,25);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feed-product-feed-0')),findsOneWidget);
    expect(find.byKey(const ValueKey('feed-product-feed-1')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
