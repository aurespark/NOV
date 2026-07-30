import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';

import 'fixtures/web_catalog_fixtures.dart';

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
        big5ChineseFixture,
        'text/html; charset=Big5',
      ),
      '中文',
    );
    expect(
      await service.decodeHtml(
        gbkChineseFixture,
        null,
      ),
      contains('中文'),
    );
    expect(
      await service.decodeHtml(utf8ChineseFixture, null),
      '繁體中文',
    );
  });

  test('rejects login, blocked and error pages', () {
    final service = resolver();
    for (final html in [blockedPageHtml, errorPageHtml]) {
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
    final service = resolver();
    final first = service.resolveDocument(
      Uri.parse('https://example.com/catalog'),
      Document.html(duplicateCatalogHtml),
    );
    final second = service.resolveDocument(
      Uri.parse('https://example.com/catalog'),
      Document.html(duplicateCatalogHtml),
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
      '/catalog': reverseCatalogPage1Html,
      '/catalog?page=2': reverseCatalogPage2Html,
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

  test('discovers a catalog from a book page and traverses numeric pages', () async {
    final pages = <String, String>{
      '/book/42': '''
        <html><head><title>測試小說</title></head><body>
          <a href="/book/42/catalog">查看全部章節</a>
        </body></html>
      ''',
      '/book/42/catalog': '''
        <html><body>
          <div class="chapters">
            <a href="/book/42/1">001 開始</a>
            <a href="/book/42/2">002 相遇</a>
            <a href="/book/42/3">003 轉折</a>
          </div>
          <nav class="pagination">
            <a href="/book/42/catalog?page=1">1</a>
            <a href="/book/42/catalog?page=2">2</a>
          </nav>
        </body></html>
      ''',
      '/book/42/catalog?page=1': '''
        <div class="chapters">
          <a href="/book/42/1">001 開始</a>
          <a href="/book/42/2">002 相遇</a>
          <a href="/book/42/3">003 轉折</a>
        </div>
      ''',
      '/book/42/catalog?page=2': '''
        <div class="chapters">
          <a href="/book/42/4">004 真相</a>
          <a href="/book/42/5">005 決定</a>
          <a href="/book/42/6">006 尾聲</a>
        </div>
      ''',
    };
    final service = resolver(
      loader: (url) async {
        final key = '${url.path}${url.hasQuery ? '?${url.query}' : ''}';
        return WebCatalogPage(
          url: url,
          bytes: Uint8List.fromList(utf8.encode(pages[key]!)),
          contentType: 'text/html; charset=utf-8',
        );
      },
    );

    final result = await service.resolve(Uri.parse('https://example.com/book/42'));

    expect(result.bestCluster!.links, hasLength(6));
    expect(result.bestCluster!.links.first.text, '001 開始');
    expect(result.bestCluster!.links.last.text, '006 尾聲');
    expect(result.diagnostics.completeness, WebCatalogCompleteness.complete);
    expect(result.diagnostics.visitedPages, 4);
  });

  test('merges multiple volume containers and repeated latest chapters', () {
    final result = resolver().resolveDocument(
      Uri.parse('https://example.com/book/42/catalog'),
      Document.html('''
        <section class="latest">
          <a href="/book/42/5">第5章 決定</a>
          <a href="/book/42/6">第6章 尾聲</a>
          <a href="/book/42/7">第7章 新篇</a>
        </section>
        <section class="volume-one">
          <a href="/book/42/1">第1章 開始</a>
          <a href="/book/42/2">第2章 相遇</a>
          <a href="/book/42/3">第3章 轉折</a>
          <a href="/book/42/4">第4章 真相</a>
        </section>
        <section class="volume-two">
          <a href="/book/42/5">第5章 決定</a>
          <a href="/book/42/6">第6章 尾聲</a>
          <a href="/book/42/7">第7章 新篇</a>
        </section>
      '''),
    );

    expect(result.bestCluster!.links.map((link) => link.href).toSet(), hasLength(7));
    expect(result.clusters.length, greaterThanOrEqualTo(2));
  });

  test('marks static HTML without chapters for dynamic fallback', () async {
    final result = await resolver(
      loader: (url) async => WebCatalogPage(
        url: url,
        bytes: Uint8List.fromList(utf8.encode(
          '<html><body><div id="app">Loading...</div></body></html>',
        )),
        contentType: 'text/html; charset=utf-8',
      ),
    ).resolve(Uri.parse('https://example.com/book/42'));

    expect(
      result.diagnostics.completeness,
      WebCatalogCompleteness.fallbackRequired,
    );
    expect(
      result.diagnostics.stopReason,
      WebCatalogStopReason.staticHtmlInsufficient,
    );
  });
}
