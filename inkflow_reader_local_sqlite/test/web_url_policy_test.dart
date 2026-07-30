import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/web_url_policy.dart';

void main() {
  const policy = WebUrlPolicy();

  group('WebUrlPolicy', () {
    test('normalizes equivalent source URLs', () {
      final first = policy.parseAndNormalize(
        'HTTPS://Example.COM:443//novel/./catalog/?utm_source=test#chapters',
      );
      final second = policy.parseAndNormalize(
        'https://example.com/novel/catalog/',
      );

      expect(first, second);
      expect(first.toString(), 'https://example.com/novel/catalog/');
    });

    test('keeps query parameters that can change content', () {
      final normalized = policy.parseAndNormalize(
        'https://example.com/catalog?page=2&book=7&fbclid=tracking',
      );

      expect(normalized.queryParameters, {'book': '7', 'page': '2'});
    });

    test('resolves relative links against the final URL', () {
      final normalized = policy.parseAndNormalize(
        '../chapter/2?utm_medium=reader',
        baseUrl: Uri.parse('https://example.com/book/catalog/page/2'),
      );

      expect(normalized.toString(), 'https://example.com/book/chapter/2');
    });

    test('rejects unsafe schemes and missing hosts', () {
      for (final value in [
        'file:///tmp/book.html',
        'content://books/1',
        'data:text/plain,book',
        'javascript:alert(1)',
        '/relative/without/base',
      ]) {
        expect(
          () => policy.parseAndNormalize(value),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('rejects loopback, link-local and private addresses', () {
      for (final value in [
        'http://localhost/book',
        'http://127.0.0.1/book',
        'http://10.1.2.3/book',
        'http://172.16.0.1/book',
        'http://192.168.1.1/book',
        'http://169.254.1.1/book',
        'http://[::1]/book',
        'http://[fd00::1]/book',
      ]) {
        expect(
          () => policy.parseAndNormalize(value),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('enforces the redirect limit', () {
      final uri = Uri.parse('https://example.com/catalog');

      expect(() => policy.validate(uri, redirectCount: 5), returnsNormally);
      expect(
        () => policy.validate(uri, redirectCount: 6),
        throwsFormatException,
      );
    });
  });
}
