import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_v3.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';

void main() {
  setUpAll(() async {
    // Test fallback metrics only, not proof of Helvetica visual fidelity.
    final sdk =
        Platform.environment['FLUTTER_ROOT'] ??
        File(
          Platform.resolvedExecutable,
        ).parent.parent.parent.parent.parent.path;
    final loader = FontLoader('Helvetica');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes(),
        ),
      ),
    );
    await loader.load();
  });
  testWidgets('Tab bar consumes bottom inset exactly once', (tester) async {
    for (final bottom in [0.0, 24.0, 34.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              viewPadding: EdgeInsets.only(bottom: bottom),
              padding: EdgeInsets.only(bottom: bottom),
            ),
            child: Scaffold(
              bottomNavigationBar: SellerTabBar(index: 0, onSelect: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SellerTabBar)).height, 56 + bottom);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Every V3 screen fits mobile widths without overflow', (
    tester,
  ) async {
    const frames = [
      '366:15805',
      '366:15855',
      '366:15903',
      '366:15936',
      '366:15969',
      '366:16062',
      '366:17304',
      '366:16208',
      '366:16277',
      '388:17542',
      '388:17641',
      '395:18004',
      '366:16333',
      '366:17044',
      '398:18182',
      '366:16467',
      '366:16501',
      '366:16552',
      '398:18347',
      '398:18420',
      '398:18510',
      '407:442',
      '407:521',
      '410:497',
      '419:530',
      '419:620',
      '428:567',
      '440:569',
      '440:641',
      '440:713',
      '440:785',
      '487:613',
      '487:614',
      '487:615',
      '487:616',
      '494:614',
      '494:630',
      '494:651',
    ];
    for (final width in [360.0, 390.0, 402.0]) {
      tester.view.physicalSize = Size(width, 874);
      tester.view.devicePixelRatio = 1;
      for (final frame in frames) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('render'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: SellerV3(
                key: ValueKey('$frame/$width'),
                api: SellerApi(),
                initialFrame: frame,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$frame width $width');
        final dest = Platform.environment['V3_SCREENSHOTS'];
        if (dest != null && width == 390) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('render')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(dest).create(recursive: true);
            await File(
              '$dest/${frame.replaceAll(':', '_')}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('No-pavilion camera action opens address, not product editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: SellerV3(api: SellerApi(), initialFrame: '419:530'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('у вас пока нет магазинов'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Камера'));
    await tester.pumpAndSettle();
    expect(find.text('добавить магазин'), findsOneWidget);
    expect(find.text('номер павильона'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  Future<void> openFrame(WidgetTester tester, String frame) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SellerV3(api: SellerApi(), initialFrame: frame),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Shop search actually filters products', (tester) async {
    await openFrame(tester, '440:713');
    await tester.enterText(find.byType(TextField), 'несуществующий товар');
    await tester.pumpAndSettle();
    expect(find.text('ничего не найдено'), findsOneWidget);
    expect(find.text('alo кроссовки'), findsNothing);
  });
  testWidgets('Back from move restores the action panel in one tap', (
    tester,
  ) async {
    await openFrame(tester, '395:18004');
    await tester.tap(find.text('перенести'));
    await tester.pumpAndSettle();
    expect(find.text('перенести товары'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('перенести товары'), findsNothing);
    expect(find.text('выбрано : 4'), findsOneWidget);
    expect(find.text('дублировать'), findsOneWidget);
  });
  testWidgets('System back returns from connected support chat', (tester) async {
    await openFrame(tester, '366:15805');
    await tester.tap(find.text('поддержка'));
    await tester.pumpAndSettle();
    // Support now opens the real chat rather than the old design placeholder.
    expect(find.byType(SadohodChatHeader), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('поддержка'), findsOneWidget);
    expect(find.byType(SadohodChatHeader), findsNothing);
  });
  testWidgets('Edit product visibility uses Figma eye icons without a menu', (
    tester,
  ) async {
    await openFrame(tester, '366:16062');
    expect(find.bySemanticsLabel('Скрыть товар'), findsOneWidget);
    expect(find.text('действия с товаром'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Скрыть товар'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Показать товар'), findsOneWidget);
    expect(find.text('Товар скрыт'), findsOneWidget);
  });

  testWidgets('Unsaved editor changes prompt before going back', (tester) async {
    await openFrame(tester, '366:16062');
    await tester.enterText(find.byType(TextField).first, 'Другое название');
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsOneWidget);
    await tester.tap(find.text('продолжить редактирование'));
    await tester.pumpAndSettle();
    expect(find.text('изменить товар'), findsOneWidget);
    expect(find.text('Несохранённые изменения'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('выйти без сохранения'));
    await tester.pumpAndSettle();
    expect(find.text('изменить товар'), findsNothing);
  });

  testWidgets('Catalog separates published and hidden items', (tester) async {
    await openFrame(tester, '366:16277');
    expect(find.text('опубликованные'), findsOneWidget);
    expect(find.text('скрытые'), findsOneWidget);
    expect(find.text('alo кроссовки'), findsWidgets);
    await tester.tap(find.text('скрытые'));
    await tester.pumpAndSettle();
    expect(find.text('alo кроссовки'), findsNothing);
  });
}
