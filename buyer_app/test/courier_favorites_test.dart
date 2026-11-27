import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/data/account.dart';

class _Account extends AccountStore {
  final remote = <String>{};
  final writes = <Map<String,dynamic>>[];
  bool fail = false;
  Completer<void>? writeGate;
  Completer<Map<String,dynamic>>? readGate;

  @override
  Future<Map<String,dynamic>> request(String route, {
    Map<String,dynamic>? body, String method = 'POST',
  }) async {
    if (route == '/account' && method == 'GET') {
      if (readGate != null) return readGate!.future;
      return {'couriers':remote.toList()};
    }
    if (route == '/account/favorite') {
      writes.add(Map.of(body!));
      if (writeGate != null) await writeGate!.future;
      if (fail) throw StateError('offline');
      final id = body['id'] as String;
      final saved = body['saved'] as bool;
      saved ? remote.add(id) : remote.remove(id);
      return {'saved':saved};
    }
    throw StateError('unexpected $method $route');
  }
}

void main() {
  test('courier toggle is optimistic, isolated, persisted and reversible', () async {
    final store = _Account()..token = 'session';
    await store.refreshCourierFavorites();
    store.writeGate = Completer<void>();
    final pending = store.toggleCourier('courier-1');
    expect(store.couriers, {'courier-1'});
    expect(store.courierFavoriteBusy('courier-1'), isTrue);
    await store.toggleCourier('courier-1');
    expect(store.writes, hasLength(1));
    store.writeGate!.complete();
    await pending;
    expect(store.remote, {'courier-1'});
    expect(store.products, isEmpty);
    expect(store.sellers, isEmpty);
    final reopened = _Account()..token = 'session';
    reopened.remote.addAll(store.remote);
    await reopened.refreshCourierFavorites();
    expect(reopened.couriers, {'courier-1'});
    await reopened.toggleCourier('courier-1');
    expect(reopened.couriers, isEmpty);
    expect(reopened.remote, isEmpty);
  });

  test('failed request rolls back the heart', () async {
    final store = _Account()..token = 'session';
    await store.refreshCourierFavorites();
    store.fail = true;
    await expectLater(store.toggleCourier('courier-1'), throwsStateError);
    expect(store.couriers, isEmpty);
    expect(store.courierFavoriteBusy('courier-1'), isFalse);
  });

  test('late account refresh cannot overwrite a new favorite', () async {
    final store = _Account()..token = 'session';
    await store.refreshCourierFavorites();
    store.readGate = Completer<Map<String,dynamic>>();
    final stale = store.refreshCourierFavorites();
    await store.toggleCourier('courier-1');
    store.readGate!.complete({'couriers':<String>[]});
    await stale;
    expect(store.couriers, {'courier-1'});
    store.token = 'new-session';
    expect(store.courierFavoritesReady, isFalse);
  });
}
