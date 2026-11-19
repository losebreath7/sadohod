import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// Guest favourites stay on this device. Auth tokens use OS secure storage.
/// Never fall back to plaintext preferences for session tokens.
class AuthStorageUnavailable implements Exception {
  const AuthStorageUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class AccountStore extends ChangeNotifier {
  static final instance = AccountStore();
  final _secure = const FlutterSecureStorage();
  final products = <String>{};
  final sellers = <String>{};
  final _saving = <String>{};
  String? token;
  String email = '', name = '';
  Uint8List? avatar, cover;
  String? syncError;
  bool get signedIn => token != null;
  int interestRevision = 0;
  void interestViewed() {
    interestRevision++;
    notifyListeners();
  }

  /// Check before requesting a one-time email code: on iPhone a plain HTTP
  /// LAN address is not a secure browser context. A code must not be consumed
  /// before we know that this browser can retain its session.
  Future<void> ensureSessionStorageReady() async {
    if (kIsWeb) {
      final uri = Uri.base;
      final trustedLocalhost =
          uri.host == 'localhost' || uri.host == '127.0.0.1';
      if (uri.scheme != 'https' && !trustedLocalhost) {
        throw const AuthStorageUnavailable(
          'Для входа с телефона откройте защищённую HTTPS-версию Садохода. '
          'По обычному HTTP браузер не может надёжно сохранить вход.',
        );
      }
    }
    const key = 'sadohod.storage.check';
    try {
      await _secure.write(key: key, value: 'ready');
      final value = await _secure.read(key: key);
      if (value != 'ready') throw StateError('Storage probe failed');
      await _secure.delete(key: key);
    } catch (_) {
      throw const AuthStorageUnavailable(
        'Защищённое хранилище браузера недоступно. '
        'Откройте Садоход через HTTPS и попробуйте ещё раз.',
      );
    }
  }
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    products.addAll(p.getStringList('guest.products') ?? []);
    sellers.addAll(p.getStringList('guest.sellers') ?? []);
    try {
      token = await _secure.read(key: 'session');
    } catch (_) {
      token = null;
    }
    if (signedIn) {
      try {
        // A prior sync failure must not lose guest favourites. Merge is
        // idempotent on the backend, so it is safe to retry at next startup.
        final guestsP = p.getStringList('guest.products') ?? [];
        final guestsS = p.getStringList('guest.sellers') ?? [];
        if (guestsP.isNotEmpty || guestsS.isNotEmpty) {
          await request('/account/merge', body: {
            'products': guestsP,
            'sellers': guestsS,
          });
        }
        await refresh();
        if (guestsP.isNotEmpty || guestsS.isNotEmpty) {
          await p.remove('guest.products');
          await p.remove('guest.sellers');
        }
      } catch (_) {
        syncError = 'Вход сохранён. Не удалось синхронизировать избранное';
      }
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> request(
    String route, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    final uri = Uri.parse('${CatalogApi.instance.baseUrl}/api/v1$route');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    late http.Response response;
    try {
      response = await (method == 'GET'
                  ? http.get(uri, headers: headers)
                  : method == 'DELETE'
                  ? http.delete(uri, headers: headers)
                  : http.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    ))
              .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Сервер не отвечает. Проверьте соединение.');
    } catch (_) {
      throw ApiException('Не удалось связаться с сервером. Проверьте интернет.');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Сервер вернул некорректный ответ.');
    }
    if (response.statusCode == 401) {
      token = null;
      email = '';
      name = '';
      avatar = null; cover = null;
      products.clear();
      sellers.clear();
      await _secure.delete(key: 'session');
      notifyListeners();
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        data['detail'] is String
            ? data['detail']
            : 'Не удалось выполнить запрос',
      );
    }
    return data;
  }

  Future<void> refresh() async {
    final data = await request('/account', method: 'GET');
    email = data['email'];
    name = data['name'];
    products
      ..clear()
      ..addAll(List<String>.from(data['products']));
    sellers
      ..clear()
      ..addAll(List<String>.from(data['sellers']));
    try {
      final media = await request('/account/media', method: 'GET');
      final image1 = media['avatar']?.toString() ?? '';
      final image2 = media['cover']?.toString() ?? '';
      avatar = image1.isEmpty ? null : base64Decode(image1);
      cover = image2.isEmpty ? null : base64Decode(image2);
    } catch (_) {
      // A media error must never invalidate an otherwise healthy session.
    }
    syncError = null;
    notifyListeners();
  }

  Future<void> verify(String address, String code) async {
    // This MUST run before the server consumes the one-time code.
    await ensureSessionStorageReady();
    final guestsP = products.toList(), guestsS = sellers.toList();
    final data = await request(
      '/auth/verify',
      body: {'email': address, 'code': code},
    );
    token = data['token'] as String;
    syncError = null;

    // The code is consumed now. A storage failure must not pretend the code
    // was invalid or erase the already-issued (in-memory) session.
    try {
      await _secure.write(key: 'session', value: token);
    } catch (_) {
      syncError = 'Вход подтверждён, но не удалось сохранить сессию. '
          'Не закрывайте эту вкладку и откройте Садоход через HTTPS.';
      notifyListeners();
      return;
    }
    notifyListeners();

    // Favourite synchronisation is not part of login success. In case of a
    // temporary API error, keep the session and retry sync on the next launch.
    try {
      await request(
        '/account/merge',
        body: {'products': guestsP, 'sellers': guestsS},
      );
      await refresh();
      final p = await SharedPreferences.getInstance();
      await p.remove('guest.products');
      await p.remove('guest.sellers');
    } catch (_) {
      syncError = 'Вход выполнен. Избранное пока не синхронизировалось.';
      notifyListeners();
    }
  }

  Future<void> toggle(String id, {bool seller = false}) async {
    final key = '$seller:$id';
    if (!_saving.add(key)) return;
    final sessionToken = token;
    final set = seller ? sellers : products;
    final was = set.contains(id);
    was ? set.remove(id) : set.add(id);
    notifyListeners();
    try {
      if (signedIn) {
        await request(
          '/account/favorite',
          body: {
            'kind': seller ? 'seller' : 'product',
            'id': id,
            'saved': !was,
          },
        );
      } else {
        final p = await SharedPreferences.getInstance();
        await p.setStringList(
          seller ? 'guest.sellers' : 'guest.products',
          set.toList(),
        );
      }
      syncError = null;
      if (!seller && signedIn) interestViewed();
    } catch (_) {
      if (token == sessionToken) {
        was ? set.add(id) : set.remove(id);
      }
      syncError = 'Не удалось сохранить. Попробуйте ещё раз.';
    }
    _saving.remove(key);
    notifyListeners();
  }

  Future<void> saveName(String value) async {
    await request('/account/profile', body: {'name': value});
    name = value;
    notifyListeners();
  }

  Future<void> saveMedia(String kind, Uint8List bytes) async {
    if (kind != 'avatar' && kind != 'cover') throw ArgumentError('Invalid media kind');
    await request('/account/media', body: {'kind': kind, 'data': base64Encode(bytes)});
    // Server reencodes the image, so refresh for the exact stored bytes.
    final data = await request('/account/media', method: 'GET');
    avatar = (data['avatar']?.toString() ?? '').isEmpty ? null : base64Decode(data['avatar']);
    cover = (data['cover']?.toString() ?? '').isEmpty ? null : base64Decode(data['cover']);
    notifyListeners();
  }

  Future<void> requestEmailChange(String newEmail) async {
    await request('/account/email/request', body: {'email': newEmail});
  }

  Future<void> confirmEmailChange(String newEmail, String code) async {
    await request('/account/email/confirm', body: {'email': newEmail, 'code': code});
    await refresh();
  }

  Future<void> logout({bool delete = false}) async {
    await request(
      delete ? '/account' : '/auth/logout',
      method: delete ? 'DELETE' : 'POST',
    );
    token = null;
    email = '';
    name = '';
    avatar = null; cover = null;
    products.clear();
    sellers.clear();
    await _secure.delete(key: 'session');
    notifyListeners();
  }
}
