import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'product_actions.dart';

class DraftForm {
  DraftForm({
    required this.title,
    required this.price,
    required this.initialPrice,
    required this.product,
    required this.original,
    required this.destinations,
    this.saleModes = const ['retail'],
    this.listingEdits = const {},
    required this.deleted,
    required this.photos,
    required this.replacements,
    required this.session,
  });
  final String title, price, initialPrice;
  final ProductData product, original;
  final List<String> saleModes;
  final Map<String, ProductData> listingEdits;
  final Set<String> destinations, deleted;
  final List<XFile> photos;
  final Map<XFile, String> replacements;
  final ProductSaveSession session;

  Future<ProductData> encode(Map<XFile, Future<String>> cache) async {
    if (photos.length > 12)
      throw Exception('Черновик: не больше 12 фотографий.');
    final files = <ProductData>[];
    for (final photo in photos) {
      if (await photo.length() > 8 * 1024 * 1024)
        throw Exception('Черновик: фотография больше 8 МБ.');
      final bytes = await cache.putIfAbsent(
        photo,
        () async => base64Encode(await photo.readAsBytes()),
      );
      files.add({
        'name': photo.name,
        'mime': photo.mimeType,
        'bytes': bytes,
        'uploadKey': session.photoKeys[photo],
        'uploaded': session.finishedPhotos.contains(photo),
        'replaceId': replacements[photo],
      });
    }
    return {
      'title': title,
      'price': price,
      'initialPrice': initialPrice,
      'saleModes': saleModes,
      'listingEdits': listingEdits,
      'product': product,
      'original': original,
      'destinations': destinations.toList(),
      'deleted': deleted.toList(),
      'photos': files,
      'session': {
        'id': session.productId,
        'createKey': session.createKey,
        'requestKeys': session.requestKeys,
      },
    };
  }

  static DraftForm decode(ProductData data) {
    final sessionData = Map<String, dynamic>.from(data['session'] as Map);
    final session = ProductSaveSession()
      ..productId = sessionData['id'] as String?
      ..createKey = sessionData['createKey'] as String;
    session.requestKeys.addAll(
      Map<String, String>.from(sessionData['requestKeys'] as Map),
    );
    final photos = <XFile>[];
    final replacements = <XFile, String>{};
    final files = dataRows(data['photos']);
    if (files.length > 12)
      throw const FormatException('Слишком много фотографий в черновике.');
    for (final file in files) {
      final encoded = file['bytes'] as String;
      if (encoded.length > 12 * 1024 * 1024)
        throw const FormatException('Слишком большая фотография.');
      final bytes = base64Decode(encoded);
      if (bytes.length > 8 * 1024 * 1024)
        throw const FormatException('Слишком большая фотография.');
      final photo = XFile.fromData(
        bytes,
        name: file['name'] as String,
        mimeType: file['mime'] as String?,
      );
      photos.add(photo);
      if (file['uploadKey'] != null)
        session.photoKeys[photo] = file['uploadKey'] as String;
      if (file['uploaded'] == true) session.finishedPhotos.add(photo);
      if (file['replaceId'] != null)
        replacements[photo] = file['replaceId'] as String;
    }
    return DraftForm(
      title: data['title'] as String,
      price: data['price'] as String,
      saleModes: List<String>.from(data['saleModes'] ?? ['retail']),
      listingEdits: (data['listingEdits'] as Map? ?? {}).map(
        (k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)),
      ),
      initialPrice: data['initialPrice'] as String,
      product: Map<String, dynamic>.from(data['product'] as Map),
      original: Map<String, dynamic>.from(data['original'] as Map),
      destinations: Set<String>.from(data['destinations'] as List),
      deleted: Set<String>.from(data['deleted'] as List),
      photos: photos,
      replacements: replacements,
      session: session,
    );
  }
}
