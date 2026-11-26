import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/api.dart';
import 'package:sadohod_seller/draft_form.dart';
import 'package:sadohod_seller/product_actions.dart';

class ActionsApi extends SellerApi {
  final requests = <Map<String, dynamic>>[];
  final keys = <String>[];
  bool loseUpload = true;
  Map<String, dynamic> current = {'id': 'p1', 'status': 'draft', 'image_items': [], 'images': []};
  @override
  Future<Map<String, dynamic>> call(String route, {String method = 'GET', Map<String, dynamic>? body}) async {
    requests.add({'route': route, 'method': method, 'body': body});
    if (route.endsWith('/save')) current = {...current, 'status': 'pending'};
    return Map.of(current);
  }
  @override
  Future<Map<String, dynamic>> uploadProductImages(String id, List<XFile> images, {String? requestId, String? replaceId}) async {
    keys.add(requestId!);
    current = {...current, 'image_items': [{'id': 'i1', 'url': '/photo.jpg'}], 'images': ['/photo.jpg']};
    if (loseUpload) { loseUpload = false; throw Exception('Response lost after server commit'); }
    return Map.of(current);
  }
}

class LostFinalResponseApi extends ActionsApi {
  LostFinalResponseApi() { loseUpload = false; }

  bool loseFinal = true;
  @override
  Future<Map<String, dynamic>> call(String route, {
    String method = 'GET', Map<String, dynamic>? body,
  }) async {
    final result = await super.call(route, method: method, body: body);
    if (route.endsWith('/save') && loseFinal) {
      loseFinal = false;
      throw Exception('Lost final response');
    }
    return result;
  }
}

void main() {
  test('save feedback reflects moderation decision, never HTTP success alone', () {
    expect(productSaveFeedback({
      'status': 'pending',
      'note': 'Автопроверка: фотография похожа на запрещённые вещества',
      'listings': [{'status': 'pending', 'published': false}],
    }), 'Товар отправлен на проверку модерации. Пока не опубликован.');
    expect(productSaveFeedback({
      'status': 'approved',
      'listings': [{'status': 'approved', 'published': true}],
    }), 'Товар опубликован');
    expect(productSaveFeedback({
      'status': 'rejected', 'listings': [],
    }), 'Товар отклонён модерацией.');
    expect(productSaveFeedback({
      'status': 'rejected', 'note': 'Фото №2: инфографика.',
    }), 'Фото №2: инфографика.');
    expect(productSaveFeedback({
      'status': 'approved', 'listings': [],
    }), 'Товар сохранён');
    expect(productSaveFeedback({
      'status': 'approved',
      'listings': [{'status': 'pending', 'published': false}],
    }), 'Товар отправлен на проверку модерации. Пока не опубликован.');
  });

  test('retry after lost photo response reuses draft and upload key', () async {
    final api = ActionsApi(); final actions = ProductActions(api);
    final session = ProductSaveSession();
    final photo = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'photo.jpg');
    Future<Map<String,dynamic>> save() => actions.save(session: session, original: {}, title: 'Худи',
      price: 1000, priceChanged: true, destinations: {'shop'}, photos: [photo], deletedPhotos: {}, replacements: {});
    await expectLater(save(), throwsException);
    expect(session.productId, 'p1');
    final result = await save();
    expect(result['status'], 'pending');
    expect(api.keys.length, 2);
    expect(api.keys[0], api.keys[1]);
    expect(api.requests.where((r) => r['route'] == '/merchant/products' && r['method'] == 'POST').length, 1);
  });

  test('restored draft replays only its own final submission', () async {
    final api = LostFinalResponseApi();
    final actions = ProductActions(api);
    var form = DraftForm(
      title: 'Худи', price: '', initialPrice: '', product: {}, original: {},
      destinations: {'shop'}, deleted: {}, replacements: {},
      photos: [XFile.fromData(Uint8List.fromList([1]), name: 'x.jpg')],
      session: ProductSaveSession(),
    );
    late ProductData snapshot;
    Future<ProductData> save(String title) => actions.save(
      session: form.session, original: form.original, title: title, price: null,
      priceChanged: false, destinations: form.destinations, photos: form.photos,
      deletedPhotos: form.deleted, replacements: form.replacements,
      checkpoint: () async { snapshot = await form.encode({}); },
    );
    await expectLater(save(form.title), throwsException);
    final originalRequest = api.requests.last;
    expect(originalRequest['route'], endsWith('/save'));
    form = DraftForm.decode(snapshot);
    await expectLater(save('Другой товар'), throwsA(isA<SellerApiException>()));
    final beforeRetry = api.requests.length;
    final result = await save(form.title);
    expect(api.requests.skip(beforeRetry).toList(), [originalRequest]);
    expect(result['status'], 'pending');
    expect(api.keys, hasLength(1));
    expect(api.requests.where((r) => r['method'] == 'POST'), hasLength(1));
  });

  test('unchanged edit retains individual pavilion prices and sale modes', () async {
    final api = ActionsApi()..loseUpload = false;
    final original = <String,dynamic>{'id': 'p1', 'image_items': [{'id': 'i1'}],
      'listings': [
        {'pavilion_id': 'a', 'price': 100, 'sale_modes': ['wholesale']},
        {'pavilion_id': 'b', 'price': 200, 'sale_modes': ['retail']},
      ]};
    await ProductActions(api).save(session: ProductSaveSession(), original: original,
      title: 'Худи', price: 100, priceChanged: false, destinations: {'a','b'}, photos: [],
      deletedPhotos: {}, replacements: {});
    final body = api.requests.last['body'] as Map;
    expect(body['listings'], original['listings']);
    expect(body['submit'], true);
  });

  test('invalid empty form sends no network mutations', () async {
    final api = ActionsApi();
    await expectLater(ProductActions(api).save(session: ProductSaveSession(), original: {}, title: '',
      price: 0, priceChanged: true, destinations: {'shop'}, photos: [], deletedPhotos: {}, replacements: {}), throwsException);
    expect(api.requests, isEmpty);
  });
}
