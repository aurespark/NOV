import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';

void main() {
  WebCatalogResolver resolver({
    WebCatalogPageLoader? loader,
    int maxPages = 50,
  }) => WebCatalogResolver(
    pageLoader: loader,
    maxCatalogPages: maxPages,
    legacyDecoder: (charset, bytes) async {
      if (charset == 'big5' && bytes.length == 4) return '中文';
      if (charset == 'gbk' && bytes.take(bytes.length - 4).isNotEmpty) {
        return '${ascii.decode(bytes.take(bytes.length - 4).toList())}中文';
      }
      throw const FormatException('fixture');
    },
  );

  test('uses header first and meta charset second without Latin-1 fallback', () async {
    final service = resolver();
    expect(
      await service.decodeHtml(
        Uint8List.fromList([164, 164, 164, 229]),
        'text/html; charset=Big5',
      ),
      '中文',
    );
    expect(
      await service.decodeHtml(
        Uint8List.fromList([
          ...ascii.encode('<meta charset="gbk">'),
          214,
          208,
          206,
          196,
        ]),
        null,
      ),
      contains('中文'),
    );
    expect(
      await service.decodeHtml(Uint8List.fromList(utf8.encode('繁體中文')), null),
      '繁體中文',
    );
  });

  test('rejects login, blocked and error pages', () {
    final service = resolver();
    for (final html in ['<body>請先登入</body>', '<body>404 Not Found</body>']) {
      expect(
        () => service.resolveDocument(
          Uri.parse('https://example.com/catalog'),
          Document.html(html),
        ),
        throwsA(isA<WebCatalogException>()),
      );
    }
  });

  test('deduplicates normalized links with deterministic order', () {
    const html = '''
      <div id="chapters">
        <a href="/c/1?utm_source=x">第1章 開端</a>
        <a href="/c/1#top">第1章 重複</a>
        <a href="/c/2">第2章 相遇</a>
        <a href="/c/3">第3章 轉折</a>
      </div>
    ''';
    final service = resolver();
    final first = service.resolveDocument(
      Uri.parse('https://example.com/catalog'),
      Document.html(html),
    );
    final second = service.resolveDocument(
      Uri.parse('https://example.com/catalog'),
      Document.html(html),
    );
    expect(first.bestCluster, isNotNull);
    expect(first.bestCluster!.links.map((item) => item.text), [
      '第1章 開端',
      '第2章 相遇',
      '第3章 轉折',
    ]);
    expect(
      first.bestCluster!.links.map((item) => item.href),
      second.bestCluster!.links.map((item) => item.href),
    );
  });

  test('follows catalog pages once and corrects a confident reverse catalog', () async {
    final pages = <String, String>{
      '/catalog': '''
        <div id="chapters">
          <a href="/c/6">第六章</a><a href="/c/5">第五章</a>
          <a href="/c/4">第四章</a>
        </div>
        <a rel="next" href="/catalog?page=2">下一頁</a>
      ''',
      '/catalog?page=2': '''
        <div id="chapters">
          <a href="/c/3">第三章</a><a href="/c/2">第二章</a>
          <a href="/c/1">第一章</a>
        </div>
        <a rel="next" href="/catalog">下一頁</a>
      ''',
    };
    final service = resolver(
      loader: (url) async => WebCatalogPage(
        url: url,
        bytes: Uint8List.fromList(utf8.encode(pages[url.path + (url.hasQuery ? '?${url.query}' : '')]!)),
        contentType: 'text/html; charset=utf-8',
      ),
    );
    final result = await service.resolve(Uri.parse('https://example.com/catalog'));
    expect(result.visitedPages, hasLength(2));
    expect(result.bestCluster!.links.map((item) => item.text), [
      '第一章',
      '第二章',
      '第三章',
      '第四章',
      '第五章',
      '第六章',
    ]);
  });

  test('parses Arabic, full-width and Chinese chapter numbers', () {
    expect(WebCatalogResolver.chapterNumber('第12章'), 12);
    expect(WebCatalogResolver.chapterNumber('第１２章'), 12);
    expect(WebCatalogResolver.chapterNumber('第一百二十三章'), 123);
    expect(WebCatalogResolver.chapterNumber('番外篇'), isNull);
  });
}
