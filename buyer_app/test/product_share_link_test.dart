import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/product_share_actions.dart';

void main() {
  test('public link uses stable HTTPS origin and encodes product ID', () {
    expect(publicProductUri('p01').toString(), 'https://api.sadohod.ru/api/v1/products/p01/share');
    expect(publicProductUri('a/b').pathSegments, ['api', 'v1', 'products', 'a/b', 'share']);
  });
}
