import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/services/content_sanitizer.dart';

void main() {
  group('ContentSanitizer Tests', () {
    test('應正確去除 HTML 標籤與特殊實體', () {
      const raw = '<script>alert("ad");</script>第一段&nbsp;內文。<style>.ad{color:red;}</style>';
      final sanitized = ContentSanitizer.sanitize(raw);

      expect(sanitized.contains('<script>'), isFalse);
      expect(sanitized.contains('<style>'), isFalse);
      expect(sanitized.contains('&nbsp;'), isFalse);
      expect(sanitized.contains('第一段 內文。'), isTrue);
    });

    test('應濾除廣告雜訊段落並套用縮排', () {
      const raw = '''
      第一段正文開始。
      請記住本站網址以防走失
      第二段正文繼續。
      ''';

      final sanitized = ContentSanitizer.sanitize(raw);

      expect(sanitized.contains('請記住本站網址以防走失'), isFalse);
      expect(sanitized.contains('    第一段正文開始。'), isTrue);
      expect(sanitized.contains('    第二段正文繼續。'), isTrue);
    });
  });
}
