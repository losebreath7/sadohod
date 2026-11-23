import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/api_base_url.dart';

void main() {
  group('Public release API origin', () {
    test('accepts stable HTTPS DNS host without binding to a VPS IP', () {
      expect(isPublicHttpsApiEndpoint('https://api.sadohod.ru'), isTrue);
      expect(isPublicHttpsApiEndpoint(' https://api.sadohod.ru/ '), isTrue);
      expect(isPublicHttpsApiEndpoint('https://api-stage.sadohod.ru'), isTrue);
    });

    test('rejects IP literals, loopback and development placeholders', () {
      for (final url in [
        '',
        'http://api.sadohod.ru',
        'http://10.0.2.2:8000',
        'https://127.0.0.1',
        'https://192.0.2.15',
        'https://[2001:db8::1]',
        'https://localhost',
        'https://api.example.com',
        'https://example.invalid',
        'https://api.sadohod.test',
      ]) {
        expect(isPublicHttpsApiEndpoint(url), isFalse, reason: url);
      }
    });

    test('rejects credentials, nonstandard ports and URL components', () {
      for (final url in [
        'https://user:pass@api.sadohod.ru',
        'https://api.sadohod.ru:8443',
        'https://api.sadohod.ru/api/v1',
        'https://api.sadohod.ru/?redirect=1',
        'https://api.sadohod.ru/#fragment',
        'https://api..sadohod.ru',
      ]) {
        expect(isPublicHttpsApiEndpoint(url), isFalse, reason: url);
      }
    });
  });
}
