import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_v3.dart';
import 'package:sadohod_seller/seller_catalog_caption.dart';
import 'package:sadohod_shared_core/chat_widgets.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

void main() {
  setUpAll(() async {
    // Load the actual shared Manrope instead of masking font issues with Roboto.
    final font = await rootBundle.load(
      'packages/sadohod_shared_core/assets/fonts/Manrope-Regular.ttf',
    );
    final loader = FontLoader(SadohodFont.family)..addFont(Future.value(font));
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
  testWidgets('Address entry offers two exclusive methods separated by or', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: SellerV3(api: SellerApi(), initialFrame: '366:15855'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Выбрать торговую зону'), findsOneWidget);
    expect(find.text('Ввести адрес целиком'), findsOneWidget);
    expect(find.text('или'), findsOneWidget);
    expect(find.text('Адреса нет в справочнике?'), findsNothing);
    await tester.tap(find.text('Ввести адрес целиком'));
    await tester.pumpAndSettle();
    expect(find.text('адрес целиком'), findsOneWidget);
    expect(find.text('торговая зона'), findsNothing);
    expect(find.text('изменить способ ввода'), findsOneWidget);
    await tester.tap(find.text('изменить способ ввода'));
    await tester.pumpAndSettle();
    expect(find.text('или'), findsOneWidget);
    await tester.tap(find.text('Выбрать торговую зону'));
    await tester.pumpAndSettle();
    expect(find.text('торговая зона'), findsOneWidget);
    expect(find.text('адрес целиком'), findsNothing);
    expect(tester.takeException(), isNull);
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
  testWidgets('Camera tab always opens capture even without a pavilion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SellerV3(api: SellerApi(), initialFrame: '419:530'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('у вас пока нет магазинов'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Камера'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller-camera-viewport')), findsOneWidget);
    expect(find.bySemanticsLabel('Снять фото'), findsOneWidget);
    expect(find.bySemanticsLabel('из галереи'), findsOneWidget);
    expect(find.text('номер павильона'), findsNothing);
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

  testWidgets('Camera preview extends below the shutter, no black band', (
    tester,
  ) async {
    await openFrame(tester, '366:15969');
    final viewport = find.byKey(const ValueKey('seller-camera-viewport'));
    final shutter = find.bySemanticsLabel('Снять фото');
    expect(viewport, findsOneWidget);
    expect(shutter, findsOneWidget);
    expect(
      tester.getBottomLeft(viewport).dy,
      greaterThan(tester.getBottomLeft(shutter).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Camera collects six photos and opens editor only on Next', (
    tester,
  ) async {
    await openFrame(tester, '366:15969');
    final dynamic state = tester.state(find.byType(SellerV3));
    final data = await rootBundle.load('assets/figma/045ce.png');
    final bytes = data.buffer.asUint8List();
    final chosen = [
      for (var i = 0; i < 7; i++)
        XFile.fromData(bytes, name: 'capture_$i.png', mimeType: 'image/png'),
    ];
    await state.pick(selected: chosen);
    await tester.pumpAndSettle();
    expect(state.screen, 'capture');
    expect(state.capturePhotos.length, 6);
    expect(find.text('6/6'), findsOneWidget);
    expect(find.text('далее'), findsOneWidget);
    expect(find.bySemanticsLabel('из галереи'), findsOneWidget);
    await tester.tap(find.text('далее'));
    await tester.pumpAndSettle();
    expect(state.screen, 'newProduct');
    expect(state.photos.length, 6);
    expect(state.capturePhotos, isEmpty);
    // Starting another product must not reopen a full 6/6 session.
    await tester.tap(find.bySemanticsLabel('Камера'));
    await tester.pumpAndSettle();
    expect(state.screen, 'capture');
    expect(state.capturePhotos, isEmpty);
    expect(find.bySemanticsLabel('Снять фото'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Switching from product editor to camera does not restore draft', (
    tester,
  ) async {
    await openFrame(tester, '366:17304');
    final dynamic state = tester.state(find.byType(SellerV3));
    await tester.tap(find.bySemanticsLabel('Камера'));
    await tester.pumpAndSettle();
    expect(state.screen, 'capture');
    expect(find.bySemanticsLabel('Снять фото'), findsOneWidget);
    expect(find.text('Незавершённый товар восстановлен'), findsNothing);
  });

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
  testWidgets('Selection action bar stays above tab bar at any scroll height',
      (tester) async {
    await openFrame(tester, '388:17641');
    final bar = find.byKey(const ValueKey('selection-actions-bar'));
    final tab = find.byType(SellerTabBar);
    expect(bar, findsOneWidget);
    expect(tab, findsOneWidget);
    final gap = tester.getTopLeft(tab).dy - tester.getBottomLeft(bar).dy;
    expect(gap, closeTo(24, 1));
    await tester.tap(find.text('действия'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('seller-actions-sheet'));
    expect(sheet, findsOneWidget);
    final modalGap = tester.getTopLeft(tab).dy -
        tester.getBottomLeft(sheet).dy;
    expect(modalGap, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editor shows one price and one mode selector with two pavilions',
      (tester) async {
    await openFrame(tester, '366:16062');
    final dynamic state = tester.state(find.byType(SellerV3));
    state.setState(() {
      state.destinations.add('p2');
    });
    await tester.pumpAndSettle();
    expect(find.text('цена'), findsOneWidget);
    expect(find.text('опт'), findsOneWidget);
    expect(find.text('розница'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shared sale-mode edits preserve a second pavilion empty price',
      (tester) async {
    await openFrame(tester, '366:16062');
    final dynamic state = tester.state(find.byType(SellerV3));
    state.originalProduct = <String, dynamic>{
      'listings': [
        {'pavilion_id': 'p1', 'price': 200, 'sale_modes': ['retail']},
        {'pavilion_id': 'p2', 'price': null, 'sale_modes': ['wholesale']},
      ],
    };
    expect(state.originalPavilionPrice('p1', 200), 200);
    expect(state.originalPavilionPrice('p2', 200), isNull);
    expect(state.originalPavilionPrice('p3', 200), 200);
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

  testWidgets('Catalog product cards show address and price above title',
      (tester) async {
    await openFrame(tester, '366:16277');
    expect(find.byType(SellerCatalogCaption), findsWidgets);
    final first = find.byType(SellerCatalogCaption).first;
    final address = find.descendant(
      of: first,
      matching: find.byKey(const ValueKey('seller-card-address')),
    );
    final price = find.descendant(
      of: first,
      matching: find.byKey(const ValueKey('seller-card-price')),
    );
    final title = find.descendant(
      of: first,
      matching: find.byKey(const ValueKey('seller-card-title')),
    );
    expect(find.descendant(of: first, matching: find.text('Б-2В-81')),
        findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('300 ₽')),
        findsOneWidget);
    expect(tester.getCenter(address).dy, closeTo(tester.getCenter(price).dy, 1));
    expect(tester.getTopLeft(title).dy,
        greaterThan(tester.getBottomLeft(address).dy));
    expect(tester.takeException(), isNull);
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
