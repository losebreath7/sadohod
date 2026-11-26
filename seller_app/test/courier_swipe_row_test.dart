import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/courier_swipe_actions.dart';
import 'package:sadohod_seller/courier_swipe_row.dart';

void main() {
  testWidgets('drag updates without waiting for an animation; release settles and reverses',
      (tester) async {
    var opened = false;
    var taps = 0;
    var actions = 0;
    const key = ValueKey('surface');
    const label = ValueKey('label');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 390, child: StatefulBuilder(
        builder: (context, setState) => CourierSwipeRow(
          opened: opened, busy: false,
          onReveal: (value) => setState(() => opened = value),
          onOpen: () => taps++,
          closedLeft: 15, openLeft: -45, closedRight: 30,
          actionInset: 10, travel: 60, surfaceKey: key,
          leadingAction: CourierSwipeAction(label: 'Collect', collect: true, onTap: () => actions++),
          trailingAction: CourierSwipeAction(label: 'Delete', remove: true, onTap: () => actions++),
          content: (_) => const Align(alignment: Alignment.centerLeft,
            child: Text('Product', key: label)),
        ),
      )),
    ))));
    final surface = find.byKey(key);
    final text = find.byKey(label);
    final originalWidth = tester.getSize(text).width;
    expect(tester.getTopLeft(surface).dx, 15);
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-24,0));
    await tester.pump();
    final x1 = tester.getTopLeft(surface).dx;
    expect(x1, lessThan(15));
    expect(x1, greaterThan(-45));
    await gesture.moveBy(const Offset(-12,0));
    await tester.pump();
    expect(tester.getTopLeft(surface).dx, closeTo(x1-12, .01));
    expect(tester.getSize(text).width, originalWidth);
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.getTopLeft(surface).dx, closeTo(x1-12,.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dx,-45);
    expect(find.bySemanticsLabel('Collect'),findsOneWidget);
    expect(find.bySemanticsLabel('Delete'),findsOneWidget);
    await tester.dragFrom(const Offset(100,28),const Offset(100,0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dx,15);
    expect(find.bySemanticsLabel('Delete'),findsNothing);
    expect(taps,0);
    expect(actions,0);
    await tester.tapAt(const Offset(100,28));
    expect(taps,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('slow short folder swipe returns to closed; cancellation does not trigger action',
      (tester) async {
    var opened = false;
    var actions = 0;
    const key = ValueKey('surface');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(
      builder:(context,setState)=>CourierSwipeRow(
        opened:opened,busy:false,
        onReveal:(value)=>setState(()=>opened=value),
        onOpen:()=>actions++,
        openLeft:-8,surfaceKey:key,
        leadingAction:CourierSwipeAction(label:'Archive',icon:Icons.archive_outlined,onTap:()=>actions++),
        trailingAction:CourierSwipeAction(label:'Delete',remove:true,onTap:()=>actions++),
        content:(_)=>const Align(alignment:Alignment.centerLeft,child:Text('Client')),
      ),
    ))));
    final surface=find.byKey(key);
    final initial=tester.getRect(surface);
    final gesture=await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-24,0));
    await tester.pump(const Duration(milliseconds:200));
    await gesture.moveBy(const Offset(-1,0));
    await tester.pump(const Duration(milliseconds:200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(surface),initial);
    expect(opened,isFalse);
    final cancelled=await tester.startGesture(tester.getCenter(surface));
    await cancelled.moveBy(const Offset(-80,0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(surface),initial);
    expect(actions,0);
    expect(tester.takeException(),isNull);
  });
}
