import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/product_actions.dart';
import 'package:sadohod_seller/draft_form.dart';
import 'package:sadohod_seller/seller_v3.dart';

import 'product_actions_test.dart' show ActionsApi;

void main() {
  test(
    'empty price and wholesale reach the API without becoming zero',
    () async {
      final api = ActionsApi()..loseUpload = false;
      await ProductActions(api).save(
        session: ProductSaveSession(),
        original: {},
        title: '',
        price: null,
        priceChanged: true,
        saleModes: ['wholesale'],
        destinations: {'a'},
        photos: [
          XFile.fromData(Uint8List.fromList([1]), name: 'image.jpg'),
        ],
        deletedPhotos: {},
        replacements: {},
      );
      final body = api.requests.last['body'] as Map;
      expect((body['listings'] as List).single, {
        'pavilion_id': 'a',
        'price': null,
        'sale_modes': ['wholesale'],
      });
    },
  );

  test(
    'editing one pavilion leaves the other price and modes unchanged',
    () async {
      final api = ActionsApi()..loseUpload = false;
      final original = <String, dynamic>{
        'id': 'p1',
        'image_items': [
          {'id': 'i1'},
        ],
        'listings': [
          {
            'pavilion_id': 'a',
            'price': 100,
            'sale_modes': ['retail'],
          },
          {
            'pavilion_id': 'b',
            'price': 200,
            'sale_modes': ['wholesale'],
          },
        ],
      };
      await ProductActions(api).save(
        session: ProductSaveSession(),
        original: original,
        title: 'Товар',
        price: 100,
        priceChanged: false,
        listingEdits: {
          'a': {
            'price': null,
            'sale_modes': ['retail', 'wholesale'],
          },
        },
        destinations: {'a', 'b'},
        photos: [],
        deletedPhotos: {},
        replacements: {},
      );
      final rows = (api.requests.last['body'] as Map)['listings'] as List;
      expect(rows[0]['price'], isNull);
      expect(rows[0]['sale_modes'], ['retail', 'wholesale']);
      expect(rows[1], (original['listings'] as List)[1]);
    },
  );

  test('batch over 20 is rejected before a network request', () async {
    final api = ActionsApi();
    await expectLater(
      ProductActions(api)
          .batch('delete', {'product_ids': List.generate(21, (i) => '$i')}),
      throwsException,
    );
    expect(api.requests, isEmpty);
  });

  test(
    'per-pavilion empty price, zero and modes survive draft recovery',
    () async {
      final form = DraftForm(
        title: '',
        price: '',
        initialPrice: '',
        product: {},
        original: {},
        destinations: {'a', 'b'},
        deleted: {},
        photos: [],
        replacements: {},
        session: ProductSaveSession(),
        saleModes: ['wholesale'],
        listingEdits: {
          'a': {
            'priceText': '',
            'sale_modes': ['wholesale'],
          },
          'b': {
            'priceText': '0',
            'sale_modes': ['retail'],
          },
        },
      );
      final recovered = DraftForm.decode(await form.encode({}));
      expect(recovered.saleModes, ['wholesale']);
      expect(recovered.listingEdits, form.listingEdits);
    },
  );

  testWidgets('pending is not published and cannot open a mutable editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SellerV3(api: SellerApi(), initialFrame: '366:16062'),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(SellerV3));
    final pending = <String, dynamic>{
      'id': 'p',
      'title': 'Ожидает',
      'status': 'pending',
      'listings': [
        {
          'pavilion_id': 'a',
          'status': 'pending',
          'price': null,
          'sale_modes': ['retail'],
        },
      ],
    };
    state.setState(() {
      state.screen = 'shop';
      state.pavilion = <String, dynamic>{'id': 'a'};
      state.products = <Map<String, dynamic>>[pending];
    });
    await tester.pumpAndSettle();
    expect(state.shown, isEmpty);
    await state.openEditProduct(pending);
    await tester.pump();
    expect(state.screen, 'shop');
    expect(
      find.text(
        'Товар на проверке. Изменения будут доступны после решения модератора.',
      ),
      findsOneWidget,
    );
  });
}
