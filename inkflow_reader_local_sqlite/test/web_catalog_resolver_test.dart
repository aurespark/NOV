import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';

void main() {
  test('web catalog resolver clusters chapter links and infers a selector', () {
    const html = '''
<!doctype html>
<html>
  <head>
    <title>午後書頁</title>
  </head>
  <body>
    <nav>
      <a href="/">首頁</a>
      <a href="/login">登入</a>
      <a href="mailto:support@example.com">客服</a>
    </nav>
    <div id="chapter-list" class="list wrap">
      <ul>
        <li><a href="/book/123/1.html">第1章 開端</a></li>
        <li><a href="/book/123/2.html">第2章 相遇</a></li>
        <li><a href="/book/123/3.html">第3章 轉折</a></li>
        <li><a href="/book/123/4.html">第4章 夜色</a></li>
      </ul>
    </div>
    <footer>
      <a href="/next">下一頁</a>
    </footer>
  </body>
</html>
''';

    final resolver = WebCatalogResolver();
    final resolution = resolver.resolveHtml(
      Uri.parse('https://example.com/catalog'),
      utf8.encode(html),
    );

    expect(resolution.pageTitle, '午後書頁');
    expect(
      resolution.links.map((link) => link.text),
      containsAll(['第1章 開端', '第2章 相遇', '第3章 轉折', '第4章 夜色']),
    );
    expect(resolution.links.any((link) => link.text == '首頁'), isFalse);
    expect(resolution.links.any((link) => link.text == '登入'), isFalse);
    expect(resolution.clusters, isNotEmpty);
    expect(resolution.bestCluster, isNotNull);
    expect(resolution.bestCluster!.titleScore, greaterThan(0.9));
    expect(resolution.bestSelector, contains('chapter-list'));
    expect(resolution.bestSelector, contains('a'));
    expect(resolution.chapterHints.first.title, '第1章 開端');
  });
}
