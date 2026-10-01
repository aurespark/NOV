import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/chapter_reader_service.dart';

void main() {
  group('增強版 ChapterContentExtractor 深度適配測試', () {
    test('能夠識別 #chaptercontent 容器並保留段落縮排', () {
      const mockHtml = '''
        <html>
          <body>
            <div id="chaptercontent">
              夜幕低垂，寒風刺骨。<br/>
              少年緊握手中的長劍，眼神堅定無比。<br/><br/>
              筆趣閣最新章節請到...
            </div>
          </body>
        </html>
      ''';

      final text = ChapterContentExtractor.extractText(mockHtml);
      expect(text, contains('夜幕低垂，寒風刺骨。'));
      expect(text, contains('少年緊握手中的長劍'));
      expect(text, isNot(contains('筆趣閣最新章節'))); // 驗證水印過濾
    });

    test('能夠識別 .novel-content 多段落結構並去除廣告導航', () {
      const mockHtml = '''
        <html>
          <body>
            <div class="ad">點擊下載 APP 免費閱讀</div>
            <article class="novel-content">
              <p>第一段：清晨的第一道陽光灑向大地。</p>
              <p>第二段：遠方的戰鼓聲隱隱傳來。</p>
            </article>
            <div class="recommend">推薦閱讀：斗破蒼穹</div>
          </body>
        </html>
      ''';

      final text = ChapterContentExtractor.extractText(mockHtml);
      expect(text, contains('第一段：清晨的第一道陽光灑向大地。'));
      expect(text, contains('第二段：遠方的戰鼓聲隱隱傳來。'));
      expect(text, isNot(contains('點擊下載 APP')));
      expect(text, isNot(contains('推薦閱讀')));
    });

    test('遇到空頁面或純廣告頁面時安全回傳空字串不崩潰', () {
      const emptyHtml = '<html><body><div class="ad">純廣告</div></body></html>';
      final text = ChapterContentExtractor.extractText(emptyHtml);
      expect(text, isEmpty);
    });
  });
}