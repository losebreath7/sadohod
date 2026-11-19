import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod/features/product/product_screen.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/device_preview_shell.dart';

Widget _dialogHost({bool frame = false}) => MaterialApp(
  builder: frame
      ? (context, child) =>
          SadohodDevicePreviewShell(forcePreview: true, child: child!)
      : null,
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showBuyerProductReportDialog(context),
          child: const Text('Открыть жалобу'),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Report dialog stays inside simulated iPhone, not desktop viewport',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_dialogHost(frame: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть жалобу'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('buyer-product-report-dialog'));
    expect(dialog, findsOneWidget);
    expect(MediaQuery.sizeOf(tester.element(dialog)), const Size(402, 874));
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(402));
    expect(tester.getSize(dialog).height, lessThanOrEqualTo(874));
    expect(find.text('Укажите причину жалобы'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Неверная фотография');
    await tester.pumpAndSettle();
    final sendButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Отправить'),
        matching: find.byType(TextButton),
      ).first,
    );
    expect(sendButton.onPressed, isNotNull);
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Report dialog and actions fit a compact 320dp phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_dialogHost());
    await tester.tap(find.text('Открыть жалобу'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('buyer-product-report-dialog'));
    expect(dialog, findsOneWidget);
    final bounds = tester.getRect(dialog);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(430));
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Report link is centered lowercase Manrope Medium 12 #A5A5A5',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BuyerProductReportButton(onPressed: () {})),
    ));
    final label = find.text('пожаловаться на товар');
    expect(label, findsOneWidget);
    final widget = tester.widget<Text>(label);
    expect(widget.style!.fontFamily, SadohodFont.family);
    expect(widget.style!.fontSize, 12);
    expect(widget.style!.fontWeight, FontWeight.w500);
    expect(widget.style!.color, const Color(0xFFA5A5A5));
    expect(widget.textAlign, TextAlign.center);
    expect(tester.getCenter(label).dx, closeTo(195, 1));
    expect(tester.takeException(), isNull);
  });
}
