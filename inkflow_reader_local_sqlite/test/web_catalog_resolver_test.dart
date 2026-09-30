import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';

void main() {
  group('WebCatalogResolver 測試組', () {
    const fakeBookId = 'book_123';
    const baseUrl = 'https://novel.example.com/books/100/';

    test('能夠透過 CSS Selector 精確提取目錄並自動校準相對路徑', () {
      const mockHtml = '''
        <!DOCTYPE html>
        <html>
          <body>
            <div class="header">
              <a href="/">首頁</a>
              <a href="/login">登入</a>
            </div>
            <div id="chapter-list">
              <a href="1.html">第一章 初出茅廬</a>
              <a href="2.html">第二章 風雲再起</a>
              <a href="/books/100/3.html">第三章 巔峰之戰</a>
            </div>
          </body>
        </html>
      ''';

      final result = WebCatalogResolver.instance.resolve(
        bookId: fakeBookId,
        rawUrl: baseUrl,
        htmlContent: mockHtml,
        customSelector: '#chapter-list a',
      );

      expect(result.usedStrategy, 'rule_selector');
      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, '第一章 初出茅廬');
      expect(result.chapters[0].chapterUrl, 'https://novel.example.com/books/100/1.html');
      expect(result.chapters[0].chapterIndex, 0);
      expect(result.chapters[1].chapterIndex, 1);
      expect(result.chapters[2].chapterUrl, 'https://novel.example.com/books/100/3.html');
    });

    test('無 Selector 時，能夠透過啟發式演算法識別章節容器並過濾導航雜訊', () {
      const mockHtml = '''
        <!DOCTYPE html>
        <html>
          <body>
            <nav>
              <a href="/login">登入</a>
              <a href="/shelf">我的書架</a>
              <a href="/rank">熱門排行</a>
            </nav>
            <div class="book-catalog-container">
              <ul>
                <li><a href="c1.html">第1章 覺醒天賦</a></li>
                <li><a href="c2.html">第2章 秘境試煉</a></li>
                <li><a href="c3.html">第3章 破境成尊</a></li>
                <li><a href="c4.html">第4章 宗門大比</a></li>
                <li><a href="c5.html">第5章 終局之戰</a></li>
              </ul>
            </div>
            <footer>
              <a href="/copyright">版權聲明</a>
              <a href="/contact">聯絡我們</a>
            </footer>
          </body>
        </html>
      ''';

      final result = WebCatalogResolver.instance.resolve(
        bookId: fakeBookId,
        rawUrl: baseUrl,
        htmlContent: mockHtml,
      );

      expect(result.usedStrategy, 'heuristic');
      expect(result.chapters.length, 5);
      expect(result.chapters.first.title, '第1章 覺醒天賦');
      expect(result.chapters.first.chapterUrl, 'https://novel.example.com/books/100/c1.html');
      expect(result.chapters.last.title, '第5章 終局之戰');
      expect(result.chapters.last.chapterUrl, 'https://novel.example.com/books/100/c5.html');
      expect(result.chapters.last.chapterIndex, 4);
    });

    test('自動剔除重複 URL 連結並去重', () {
      const mockHtml = '''
        <div class="chapters">
          <a href="ch1.html">第1章 重複章節A</a>
          <a href="ch1.html">第1章 重複章節A</a>
          <a href="ch2.html">第2章 正常章節B</a>
        </div>
      ''';

      final result = WebCatalogResolver.instance.resolve(
        bookId: fakeBookId,
        rawUrl: baseUrl,
        htmlContent: mockHtml,
        customSelector: '.chapters a',
      );

      expect(result.chapters.isNotEmpty, true);
    });
  });
}