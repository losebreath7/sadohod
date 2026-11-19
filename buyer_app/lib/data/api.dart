import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'package:sadohod_shared_core/api_base_url.dart';

/// API_BASE_URL overrides the Android emulator (10.0.2.2) / web localhost default.
/// USE_LOCAL_DEMO is deliberately opt-in. It never fakes image-search results.
class CatalogApi {
  CatalogApi._();
  static final CatalogApi instance = CatalogApi._();
  static const localDemo = bool.fromEnvironment(
    'USE_LOCAL_DEMO',
    defaultValue: false,
  );
  static const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  String get baseUrl => sadohodApiBaseUrl(configuredBaseUrl);

  String absoluteUrl(String path) =>
      path.startsWith('http') ? path : '$baseUrl$path';
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> _get(String route) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl$route'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw ApiException('Ошибка сервера: ${res.statusCode}');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) {
        throw ApiException('Некорректный ответ сервера');
      }
      return body;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Нет соединения с сервером. Проверьте, что FastAPI запущен по адресу $baseUrl',
      );
    }
  }

  Future<List<DemoProduct>> products() async {
    if (localDemo) return DemoCatalog.products;
    final items = <DemoProduct>[];
    for (var offset = 0; ; offset += 500) {
      final response = await _get('/api/v1/products?limit=500&offset=$offset');
      final batch = (response['items'] as List)
          .map((v) => DemoProduct.fromJson(v as Map<String, dynamic>, baseUrl))
          .toList();
      items.addAll(batch);
      if (batch.length < 500) return items;
    }
  }

  /// Server-backed title, taxonomy and optional image-semantic search.
  /// Local demo remains strictly text-only: no invented image recognition.
  Future<List<DemoProduct>> searchText(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) return products();
    if (localDemo) {
      final q = needle.toLowerCase();
      return DemoCatalog.products.where((p) =>
        '${p.title} ${p.category} ${p.pavilion}'
          .toLowerCase().contains(q)).toList();
    }
    final route = '/api/v1/search/text?q=${Uri.encodeQueryComponent(needle)}&limit=100';
    final response = await _get(route);
    return (response['items'] as List)
      .map((v) => DemoProduct.fromJson(v as Map<String, dynamic>, baseUrl))
      .toList();
  }

  /// Personalized tags are returned only for signed-in buyers.
  /// Empty results keep the approved default chip row unchanged.
  Future<List<String>> recommendedTags(String token) async {
    if (localDemo) return const [];
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/account/interests/tags'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => item['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .take(5).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> categories() async {
    if (localDemo) return DemoCatalog.categories;
    final response = await _get('/api/v1/categories');
    return (response['items'] as List).map((v) => v.toString()).toList();
  }

  Future<DemoProduct?> product(String id) async {
    if (localDemo) return DemoCatalog.findProduct(id);
    try {
      final response = await _get(
        '/api/v1/products/${Uri.encodeComponent(id)}',
      );
      return DemoProduct.fromJson(response, baseUrl);
    } on ApiException catch (e) {
      if (e.message == 'Ошибка сервера: 404') return null;
      rethrow;
    }
  }

  Future<SellerPage?> seller(String id) async {
    if (localDemo) {
      final seller = DemoCatalog.findSeller(id);
      if (seller == null) return null;
      return SellerPage(
        seller,
        DemoCatalog.products.where((p) => p.sellerId == id).toList(),
      );
    }
    try {
      final response = await _get('/api/v1/sellers/${Uri.encodeComponent(id)}');
      return SellerPage(
        Seller.fromJson(response),
        (response['products'] as List)
            .map((v) => DemoProduct.fromJson(v as Map<String, dynamic>, baseUrl))
            .toList(),
        pavilions: (response['pavilions'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((v) => v['code']?.toString() ?? '')
            .where((v) => v.isNotEmpty).toList(),
      );
    } on ApiException catch (e) {
      if (e.message == 'Ошибка сервера: 404') return null;
      rethrow;
    }
  }

  Future<ImageSearchResponse> searchImage(
    Uint8List bytes, {
    String? crop,
  }) async {
    if (localDemo) {
      throw ApiException(
        'Офлайн-каталог не поддерживает поиск по фотографии. Запустите сервер.',
      );
    }
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/search/image'),
    );
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'query.jpg'),
    );
    if (crop != null && crop.isNotEmpty) req.fields['crop'] = crop;
    try {
      final streamed = await _client
          .send(req)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final detail = body['detail'];
        throw ApiException(
          detail is String
              ? detail
              : 'Сервер отклонил изображение (${response.statusCode})',
        );
      }
      final matches = (body['items'] as List).map((v) {
        final m = v as Map<String, dynamic>;
        return ImageMatch(
          DemoProduct.fromJson(m['product'] as Map<String, dynamic>, baseUrl),
          (m['score'] as num).toDouble(),
        );
      }).toList();
      return ImageSearchResponse(
        matches,
        body['notice']?.toString() ??
            'Визуально похожие товары. Точное совпадение не подтверждено.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Не удалось выполнить поиск. Проверьте соединение и попробуйте ещё раз.',
      );
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SellerPage {
  const SellerPage(this.seller, this.products, {this.pavilions = const []});
  final Seller seller;
  final List<DemoProduct> products;
  final List<String> pavilions;
}

class ImageMatch {
  const ImageMatch(this.product, this.rawScore);
  final DemoProduct product;

  /// Cosine similarity, NOT a calibrated percentage of correctness.
  final double rawScore;
}

class ImageSearchResponse {
  const ImageSearchResponse(this.matches, this.notice);
  final List<ImageMatch> matches;
  final String notice;
}

class ImageSearchQuery {
  const ImageSearchQuery(this.bytes, {this.crop});
  final Uint8List bytes;
  final String? crop; // normalized x,y,width,height
}
