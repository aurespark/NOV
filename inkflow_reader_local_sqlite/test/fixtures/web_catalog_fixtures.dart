import 'dart:convert';
import 'dart:typed_data';

const staticCatalogHtml = '''
<html><head><meta charset="utf-8"><title>午後書頁</title></head>
<body><div id="chapters">
  <a href="/c/1">第1章 開端</a>
  <a href="/c/2">第2章 相遇</a>
  <a href="/c/3">第3章 轉折</a>
</div></body></html>
''';

const duplicateCatalogHtml = '''
<div id="chapters">
  <a href="/c/1?utm_source=x">第1章 開端</a>
  <a href="/c/1#top">第1章 重複</a>
  <a href="/c/2">第2章 相遇</a>
  <a href="/c/3">第3章 轉折</a>
</div>
''';

const reverseCatalogPage1Html = '''
<div id="chapters">
  <a href="/c/6">第六章</a><a href="/c/5">第五章</a>
  <a href="/c/4">第四章</a>
</div>
<a rel="next" href="/catalog?page=2">下一頁</a>
''';

const reverseCatalogPage2Html = '''
<div id="chapters">
  <a href="/c/3">第三章</a><a href="/c/2">第二章</a>
  <a href="/c/1">第一章</a>
</div>
<a rel="next" href="/catalog">下一頁</a>
''';

const blockedPageHtml = '<body>請先登入並完成 CAPTCHA</body>';
const errorPageHtml = '<body>404 Not Found</body>';

final utf8ChineseFixture = Uint8List.fromList(utf8.encode('繁體中文'));
final big5ChineseFixture = Uint8List.fromList([164, 164, 164, 229]);
final gbkChineseFixture = Uint8List.fromList([
  ...ascii.encode('<meta charset="gbk">'),
  214,
  208,
  206,
  196,
]);
