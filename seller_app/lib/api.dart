import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sadohod_shared_core/api_base_url.dart';

class SellerApiException implements Exception {
  SellerApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

class SellerApi extends ChangeNotifier {
  static const configuredUrl = String.fromEnvironment('API_BASE_URL');
  static const _storage = FlutterSecureStorage();
  String? token;
  bool courierRole = false;

  Future<void> selectRole(bool courier) async {
    if (signedIn) throw StateError('Сначала выйдите из аккаунта.');
    courierRole = courier;
  }
  String get baseUrl => sadohodApiBaseUrl(configuredUrl);
  bool get signedIn => token != null;

  Future<void> restore() async {
    try {
      token = await _storage.read(key: 'seller.session');
      courierRole = await _storage.read(key: 'seller.role') == 'courier';
    } catch (_) {
      token = null;
    }
    notifyListeners();
  }

  Future<void> ensureStorageReady() async {
    if (kIsWeb &&
        Uri.base.scheme != 'https' &&
        Uri.base.host != 'localhost' &&
        Uri.base.host != '127.0.0.1') {
      throw Exception('Для входа с телефона откройте приложение по HTTPS.');
    }
    try {
      await _storage.write(key: 'seller.storage.check', value: 'ok');
      if (await _storage.read(key: 'seller.storage.check') != 'ok')
        throw StateError('Storage unavailable');
      await _storage.delete(key: 'seller.storage.check');
    } catch (_) {
      throw Exception('Защищённое хранилище недоступно. Используйте HTTPS.');
    }
  }

  Future<Map<String, dynamic>> call(
    String route, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    http.Response response;
    try {
      response = await http.Request(
        method,
        Uri.parse('$baseUrl/api/v1$route'),
      ).letSend(token, body).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw Exception('Не удалось связаться с сервером $baseUrl');
    }
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Сервер вернул некорректный ответ');
    }
    if (response.statusCode == 401) {
      await logout();
      throw Exception('Сессия истекла. Войдите снова.');
    }
    if (response.statusCode >= 400) {
      final detail = data['detail'];
      throw SellerApiException(
        response.statusCode,
        detail is String
            ? detail
            : detail is List
            ? detail
                  .map((e) => e is Map ? '${e['loc']}: ${e['msg']}' : '$e')
                  .join('; ')
            : 'Ошибка ${response.statusCode}',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> uploadProductImages(
    String productId,
    List<XFile> images, {
    String? requestId,
    String? replaceId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/merchant/products/$productId/images'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (requestId != null) request.fields['request_id'] = requestId;
    if (replaceId != null) request.fields['replace_id'] = replaceId;
    for (final file in images) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    }
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode == 401) {
      await logout();
      throw Exception('Сессия истекла. Войдите снова.');
    }
    if (response.statusCode >= 400) {
      dynamic detail;
      try {
        detail = jsonDecode(utf8.decode(response.bodyBytes))['detail'];
      } catch (_) {}
      throw Exception(
        detail is String
            ? detail
            : 'Не удалось загрузить фотографию (${response.statusCode}). Повторите сохранение.',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> requestCode(String email) async {
    await ensureStorageReady();
    await call('/auth/code', method: 'POST', body: {'email': email.trim()});
  }

  Future<void> verify(String email, String code) async {
    final result = await call(
      '/auth/verify',
      method: 'POST',
      body: {'email': email.trim(), 'code': code.trim()},
    );
    final newToken = result['token'];
    if (newToken is! String || newToken.isEmpty)
      throw Exception('Сервер не вернул токен');
    await _storage.write(key: 'seller.role', value: courierRole ? 'courier' : 'seller');
    await _storage.write(key: 'seller.session', value: newToken);
    token = newToken;
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    await _storage.delete(key: 'seller.session');
    notifyListeners();
  }
}

extension _RequestSender on http.Request {
  Future<http.Response> letSend(
    String? token,
    Map<String, dynamic>? body,
  ) async {
    headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null) this.body = jsonEncode(body);
    final streamed = await send().timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }
}
