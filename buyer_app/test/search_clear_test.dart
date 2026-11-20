import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/core/widgets/design.dart';

void main() {
  testWidgets('Search clear appears only for entered text and retains focus', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? lastValue;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SearchCapsule(
        controller: controller,
        onChanged: (v) => lastValue = v,
      ),
    ))));
    expect(find.byKey(const ValueKey('search-clear')), findsNothing);
    await tester.enterText(find.byType(TextField), 'куртка');
    await tester.pump();
    expect(find.byKey(const ValueKey('search-clear')), findsOneWidget);
    expect(controller.text, 'куртка');
    await tester.tap(find.byKey(const ValueKey('search-clear')));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(lastValue, '');
    expect(find.byKey(const ValueKey('search-clear')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ??
        FocusManager.instance.primaryFocus != null, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear button and photo search remain available together', (tester) async {
    final controller = TextEditingController(text: 'сумка');
    addTearDown(controller.dispose);
    var photoPressed = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SearchCapsule(
        controller: controller,
        onPhotoTap: () => photoPressed = true,
      ),
    ))));
    expect(find.byKey(const ValueKey('search-clear')), findsOneWidget);
    await tester.tap(find.byTooltip('Поиск по фотографии'));
    await tester.pump();
    expect(photoPressed, isTrue);
    expect(controller.text, 'сумка');
  });
}
