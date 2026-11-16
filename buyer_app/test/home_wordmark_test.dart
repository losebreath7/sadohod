import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/features/home/home_screen.dart';

void main() {
  testWidgets('Figma wordmark paints visible pixels without SVG assets',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          child: Center(child: SadohodWordmark()),
        ),
      ),
    ));
    await tester.pump();

    final logo = find.byType(SadohodWordmark);
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(98, 13));
    expect(tester.takeException(), isNull);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    final data = bytes!.buffer.asUint8List();
    var darkPixels = 0;
    for (var i = 0; i + 3 < data.length; i += 4) {
      if (data[i + 3] > 0 &&
          data[i] < 80 && data[i + 1] < 80 && data[i + 2] < 80) {
        darkPixels++;
      }
    }
    expect(darkPixels, greaterThan(100),
        reason: 'Native Figma wordmark must not render blank');
  });
}
