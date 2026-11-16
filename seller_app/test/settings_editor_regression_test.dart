import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/seller_v3.dart';

class _FakeSellerSettingsApi extends SellerApi {
  _FakeSellerSettingsApi() { token = 'test-only-session'; }

  @override
  Future<Map<String, dynamic>> call(String route,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    return <String, dynamic>{};
  }
}

void main() {
  Future<void> setUpPreview(WidgetTester tester, String screen) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: SellerV3(
        api: _FakeSellerSettingsApi(),
        initialFrame: screen,
      ),
    ));
    await tester.pumpAndSettle();
  }

  tearDown(() {});

  testWidgets('seller settings mirror buyer without duplicated notifications',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setUpPreview(tester, '366:15805');
    await tester.tap(find.text('настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Язык'), findsOneWidget);
    expect(find.text('Тема'), findsOneWidget);
    expect(find.text('Очистить кэш'), findsOneWidget);
    expect(find.text('О приложении'), findsOneWidget);
    expect(find.text('Пользовательское соглашение'), findsOneWidget);
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    expect(find.text('выйти из аккаунта'), findsOneWidget);
    expect(find.text('удалить аккаунт'), findsOneWidget);
    expect(find.text('Уведомления'), findsNothing);

    await tester.tap(find.text('О приложении'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Приложение для продавцов'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Язык'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('поддержка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor uses actions menu and pavilion code is not duplicated',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setUpPreview(tester, '366:16062');
    expect(find.text('изменить товар'), findsOneWidget);
    expect(find.text('Б-2В-81'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('действия с товаром'), findsOneWidget);
    expect(find.text('изменить фотографии'), findsOneWidget);
    expect(find.text('Очистить форму'), findsOneWidget);
    expect(find.text('отмена'), findsOneWidget);
    expect(find.text('закрыть'), findsNothing);
    await tester.tap(find.text('отмена'));
    await tester.pumpAndSettle();
    expect(find.text('действия с товаром'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
