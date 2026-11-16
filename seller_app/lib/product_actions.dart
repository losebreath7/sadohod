import 'dart:convert';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'api.dart';

typedef ProductData = Map<String, dynamic>;
String operationId() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
List<ProductData> dataRows(dynamic value) => (value as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();

/// Keys live as long as the open form. The server commits them together with
/// mutations, so a lost HTTP response does not create a second product/photo.
class ProductSaveSession {
  String? productId;
  String createKey = operationId();
  final photoKeys = <XFile, String>{};
  final finishedPhotos = <XFile>{};
  final requestKeys = <String, String>{};
  String keyFor(ProductData body) => requestKeys.putIfAbsent(jsonEncode(body), operationId);
}

class ProductActions {
  ProductActions(this.api);
  final SellerApi api;
  final batchKeys = <String, String>{};

  Future<void> batch(String action, ProductData parameters) async {
    final signature = jsonEncode({'action': action, ...parameters});
    final key = batchKeys.putIfAbsent(signature, operationId);
    await api.call('/merchant/products/actions/$action', method: 'POST', body: {'request_id': key, ...parameters});
    batchKeys.remove(signature);
  }

  Future<ProductData> save({required ProductSaveSession session, required ProductData original,
    required String title, required int price, required bool priceChanged,
    required Set<String> destinations, required List<XFile> photos,
    required Set<String> deletedPhotos, required Map<XFile, String> replacements,
    Future<void> Function()? checkpoint}) async {
    if (destinations.isEmpty) throw Exception('Выберите хотя бы один магазин.');
    final retained = dataRows(original['image_items']).where((i) => !deletedPhotos.contains(i['id'])).length;
    if (retained + photos.length == 0) throw Exception('Добавьте хотя бы одну фотографию.');
    if (retained + photos.length > 12) throw Exception('На товар можно добавить не больше 12 фотографий.');
    for (final photo in photos) {
      if (await photo.length() > 8 * 1024 * 1024) throw Exception('Фотография ${photo.name} больше 8 МБ.');
    }
    final metadata = <String, dynamic>{'title': title.trim(), 'category': original['category'] ?? '',
      'description': original['description'] ?? '', 'colors': original['colors'] ?? [], 'sizes': original['sizes'] ?? []};
    await checkpoint?.call();
    session.productId ??= original['id'] as String?;
    if (session.productId == null) {
      final created = await api.call('/merchant/products', method: 'POST', body: {...metadata, 'request_id': session.createKey});
      session.productId = '${created['id']}';
      await checkpoint?.call();
    }
    final id = session.productId!;
    var current = await api.call('/merchant/products/$id');
    final originalListings = dataRows(original['listings']);
    final fallbackModes = originalListings.isEmpty ? <String>['retail'] : List<String>.from(originalListings.first['sale_modes'] ?? ['retail']);
    final listingData = destinations.map((destination) {
      final existing = originalListings.where((l) => l['pavilion_id'] == destination).firstOrNull;
      return <String, dynamic>{'pavilion_id': destination,
        'price': !priceChanged && existing != null ? existing['price'] : price,
        'sale_modes': existing?['sale_modes'] ?? fallbackModes};
    }).toList();
    final finalBody = <String, dynamic>{...metadata, 'listings': listingData, 'submit': true};
    final finalKey = session.keyFor(finalBody);
    await checkpoint?.call();
    if (current['status'] == 'pending') {
      // A lost final response is recovered by the same receipt on the server.
      return api.call('/merchant/products/$id/save', method: 'PUT', body: {...finalBody, 'request_id': finalKey});
    }
    if (current['status'] == 'approved') {
      current = await api.call('/merchant/products/$id', method: 'PUT', body: metadata);
    }
    // Upload replacements first: a bad new file must not delete the old image.
    for (final photo in photos) {
      if (session.finishedPhotos.contains(photo)) continue;
      final key = session.photoKeys.putIfAbsent(photo, operationId);
      await checkpoint?.call();
      await api.uploadProductImages(id, [photo], requestId: key, replaceId: replacements[photo]);
      session.finishedPhotos.add(photo);
      await checkpoint?.call();
    }
    current = await api.call('/merchant/products/$id');
    final existingIds = dataRows(current['image_items']).map((i) => '${i['id']}').toSet();
    for (final imageId in deletedPhotos) {
      if (existingIds.contains(imageId)) {
        await api.call('/merchant/products/$id/images/$imageId', method: 'DELETE');
      }
    }
    return api.call('/merchant/products/$id/save', method: 'PUT', body: {...finalBody, 'request_id': finalKey});
  }
}
