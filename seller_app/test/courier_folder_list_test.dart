import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/courier_folder_list.dart';

void main() {
  testWidgets('folder actions are hidden until swipe and restore is available in archive', (tester) async {
    var archived = false;
    var removed = false;
    Future<void> render(bool inArchive) => tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(30), child: CourierFolderList(
        key: ValueKey(inArchive),
        folders: [{'id':'a','name':'Маша','note':'понедельник','count':2,'collected_count':1,'archived':inArchive}],
        archived: inArchive,
        onOpen: (_) async {},
        onArchive: (_) async { archived = true; },
        onDelete: (_) async { removed = true; },
      ),
    ))));
    await render(false);
    expect(find.bySemanticsLabel('Удалить папку'), findsNothing);
    await tester.drag(find.text('Маша'), const Offset(-150,0));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('В архив'));
    await tester.pumpAndSettle();
    expect(archived, isTrue);
    await render(true);
    await tester.drag(find.text('Маша'), const Offset(-150,0));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Вернуть из архива'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Удалить папку'));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
