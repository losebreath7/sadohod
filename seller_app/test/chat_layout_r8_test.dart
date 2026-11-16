import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';

void main() {
  testWidgets('composer grows for multiline input and caps its height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.bottomCenter,
      child: SadohodChatComposer(
        controller: controller, onSend: () {}, onAttachment: () {},
      ),
    ))));

    final first = tester.getSize(find.byType(SadohodChatComposer)).height;
    await tester.enterText(find.byType(TextField),
        'Первая строка\nВторая строка\nТретья строка\nЧетвёртая строка');
    await tester.pumpAndSettle();
    final expanded = tester.getSize(find.byType(SadohodChatComposer)).height;
    expect(expanded, greaterThan(first));
    await tester.enterText(find.byType(TextField),
        List.filled(25, 'Длинная строка').join('\n'));
    await tester.pumpAndSettle();
    final capped = tester.getSize(find.byType(SadohodChatComposer)).height;
    expect(capped, lessThan(155));
    expect(find.bySemanticsLabel('Отправить сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer centers hint and input with matching line height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.bottomCenter,
      child: SadohodChatComposer(
        controller: controller, onSend: () {}, onAttachment: () {},
      ),
    ))));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'сообщение');
    expect(field.decoration?.isDense, true);
    expect(field.decoration?.contentPadding,
        const EdgeInsets.symmetric(vertical: 12));
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(field.minLines, 1);
    expect(field.maxLines, 5);
    expect(tester.getSize(find.byType(SadohodChatComposer)).height,
        inInclusiveRange(43, 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('only outgoing messages receive a sent checkmark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SadohodChatBubble(text: 'Привет!', mine: true,
        sent: 1731769200),
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SadohodChatBubble(text: 'Привет!', mine: false,
        sent: 1731769200),
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long bubble includes time without a positioned overlay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SadohodChatBubble(
        text: 'Очень длинное сообщение для проверки переносов, и ещё '
            'несколько слов для переноса внутри пузыря.',
        mine: true, sent: 1731769200,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(SadohodChatBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
