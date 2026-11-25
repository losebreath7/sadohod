import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_seller/sadohodets_cabinet.dart';
void main() {
  test('client links accept HTTPS and reject arbitrary schemes', () {
    expect(clientContactUri(' https://t.me/example_client ')?.host, 't.me');
    expect(clientContactUri('https://wa.me/79990000000')?.host, 'wa.me');
    for (final value in ['', 'javascript:alert(1)', 'http://example.com', 'https://', 'https://user@example.com', 'https://example.com/a b']) {
      expect(clientContactUri(value), isNull);
    }
  });
}
