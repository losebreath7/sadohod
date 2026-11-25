import 'package:sadohod_shared_core/product_share_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/api.dart';
import '../lib/sadohodets_api.dart';

class FakeApi extends SellerApi {
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> response = {};
  int? error;
  @override
  Future<Map<String, dynamic>> call(String route, {String method = 'GET', Map<String, dynamic>? body}) async {
    calls.add({'route': route, 'method': method, 'body': body});
    if (error != null) throw SellerApiException(error!, 'test');
    return response;
  }
}

void main() {
  test('client folders accept the URL produced by both product buttons', () {
    final link = publicProductUri('folder-product').toString();
    expect(productIdFromShareLink(link), 'folder-product');
    expect(productIdFromShareLink(link.replaceFirst('api.sadohod.ru', 'example.org')), isNull);
    expect(productIdFromShareLink('$link/extra'), isNull);
  });
  test('profile absence is distinct from an authorization failure', () async {
    final fake = FakeApi();
    final api = SadohodetsApi(fake);
    fake.error = 404;
    expect(await api.profile(), isNull);
    fake.error = 403;
    await expectLater(api.profile(), throwsA(isA<SellerApiException>()));
  });
  test('collection uses encoded IDs and independent PATCH action', () async {
    final fake = FakeApi();
    final api = SadohodetsApi(fake);
    await api.setCollected('folder/a', 'item/b', true);
    expect(fake.calls.single, {
      'route': '/sadohodets/me/folders/folder%2Fa/items/item%2Fb',
      'method': 'PATCH', 'body': {'collected': true},
    });
  });
  test('publication remains a separate explicit request', () async {
    final fake = FakeApi();
    final api = SadohodetsApi(fake);
    await api.saveProfile(name: 'Анна', contacts: {'phone': '+79991234567'});
    await api.publication(true);
    expect(fake.calls.first['route'], '/sadohodets/me');
    expect(fake.calls.last['body'], {'published': true});
  });
}
