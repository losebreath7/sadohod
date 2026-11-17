import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/features/home/home_screen.dart';

void main() {
  testWidgets('Figma wordmark is native custom-painted at original dimensions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: SadohodWordmark()),
      ),
    ));
    await tester.pump();

    final logo = find.byType(SadohodWordmark);
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(98, 13));
    final paint = find.descendant(
      of: logo,
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsOneWidget);
    expect(tester.widget<CustomPaint>(paint).painter, isNotNull);
    expect(tester.takeException(), isNull);
    // Real browser screenshot CI verifies that the painter produces
    // visible pixels. Awaiting RenderRepaintBoundary.toImage() inside a
    // synchronous widget test hung the test runner for ten minutes.
  });
}
