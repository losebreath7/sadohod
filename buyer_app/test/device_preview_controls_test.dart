import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sadohod_shared_core/device_preview_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop device selector and overlay dialog are interactive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SadohodDevicePreviewShell(
        forcePreview: true, child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('device-lab-smoke'))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('iPhone 16 Pro ·'), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-lab-model')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Galaxy A15').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Galaxy A15 ·'), findsOneWidget);

    await tester.tap(find.text('Без рамки'));
    await tester.pumpAndSettle();
    expect(find.text('С рамкой'), findsOneWidget);
    await tester.tap(find.text('С рамкой'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Своя модель'));
    await tester.pumpAndSettle();
    expect(find.text('Параметры устройства'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'QA Compact');
    await tester.tap(find.text('Применить и сохранить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('QA Compact ·'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sadohod_device_lab_custom_presets_v1'), isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
