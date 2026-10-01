import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/online_chapter_service.dart';

void main() {
  group('【階段一單元測試】小說正文提取與廣告清洗', () {
    test('1-1 提取 div.content 正文並過濾 script 與廣告', () {
      const html = '''
        <html>
          <body>
            <div class="content">
              <script>var ad = 1;</script>
              第一行小說內文。<br>第二行小說內文。
              <p>第三段段落內容。</p>
              <ins class="adsbygoogle">廣告橫幅</ins>
            </div>
          </body>
        </html>
      ''';

      final clean = OnlineChapterService.extractText(html);

      expect(clean, contains('第一行小說內文。'));
      expect(clean, contains('第二行小說內文。'));
      expect(clean, contains('第三段段落內容。'));
      expect(clean, isNot(contains('ad = 1')));
      expect(clean, isNot(contains('廣告橫幅')));
      expect(clean, isNot(contains('<br>')));
    });

    test('1-2 空字串與無效標籤防呆', () {
      expect(OnlineChapterService.extractText(''), '');
      expect(OnlineChapterService.extractText('   '), '');
    });
  });
}
