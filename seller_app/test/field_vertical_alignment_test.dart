import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/seller_v3.dart';

void main() {
  for (final width in <double>[390, 402]) {
    for (final showTitle in <bool>[true, false]) {
      testWidgets('input is vertically centered: $width / title $showTitle', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController(text: 'Тестовый текст');
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
          child: SizedBox(width: 330,
            child: V3Field('название', controller, showTitle: showTitle)),
        ))));
        final field = tester.getRect(find.byType(V3Field));
        final edit = tester.getRect(find.byType(EditableText));
        expect((field.center.dy - edit.center.dy).abs(), lessThan(5));
      });
    }
  }
}
