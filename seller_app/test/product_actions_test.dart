import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/api.dart';
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
  Future<void> uploadProductImages(String id, List<XFile> images, {String? requestId, String? replaceId}) async {
    keys.add(requestId!);
    current = {...current, 'image_items': [{'id': 'i1', 'url': '/photo.jpg'}], 'images': ['/photo.jpg']};
    if (loseUpload) { loseUpload = false; throw Exception('Response lost after server commit'); }
  }
}

void main() {
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
