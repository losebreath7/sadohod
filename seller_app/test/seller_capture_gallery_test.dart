import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/seller_capture_gallery.dart';
import 'package:sadohod_shared_core/device_preview_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<XFile>> _sixPictures() async {
  final asset = await rootBundle.load('assets/figma/045ce.png');
  final bytes = Uint8List.fromList(asset.buffer.asUint8List());
  return [
    for (var i = 0; i < 6; i++)
      XFile.fromData(bytes, name: 'photo_$i.png', mimeType: 'image/png'),
  ];
}

Widget _testApp(List<XFile> pictures, {bool previewShell = false}) =>
    MaterialApp(
      builder: previewShell
          ? (context, child) =>
              SadohodDevicePreviewShell(forcePreview: true, child: child!)
          : null,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSellerCaptureGallery(
                context: context,
                photos: pictures,
                onRemove: pictures.remove,
              ),
              child: const Text('Открыть фотографии'),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Photo gallery dialog stays inside the simulated iPhone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photos = await _sixPictures();

    await tester.pumpWidget(_testApp(photos, previewShell: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть фотографии'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const ValueKey('seller-capture-gallery-dialog'),
    );
    expect(dialog, findsOneWidget);
    // The outer browser Navigator is 1440x1000, but the device Navigator
    // must provide the phone's own MediaQuery to the modal.
    expect(MediaQuery.sizeOf(tester.element(dialog)), const Size(402, 874));
    // AlertDialog itself can span the available overlay; the inner Material
    // is the actual white card and must respect the 16dp side insets.
    final card = find.descendant(
      of: dialog,
      matching: find.byType(Material),
    ).first;
    expect(tester.getSize(card).width, lessThanOrEqualTo(402 - 32));
    expect(tester.getSize(card).height, lessThanOrEqualTo(874 - 32));
    expect(find.text('фотографии 6/6'), findsOneWidget);
    expect(find.text('закрыть'), findsOneWidget);

    await tester.tap(find.byTooltip('Удалить фотографию').first);
    await tester.pumpAndSettle();
    expect(photos.length, 5);
    expect(find.text('фотографии 5/6'), findsOneWidget);
    await tester.tap(find.text('закрыть'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photo gallery dialog fits a compact phone and scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photos = await _sixPictures();

    await tester.pumpWidget(_testApp(photos));
    await tester.tap(find.text('Открыть фотографии'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const ValueKey('seller-capture-gallery-dialog'),
    );
    expect(dialog, findsOneWidget);
    final bounds = tester.getRect(dialog);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(430));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
