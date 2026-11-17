import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inkflow_reader/src/core/services/novel_html_extractor.dart';
import 'package:inkflow_reader/src/core/services/online_chapter_service.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';
import 'package:sqflite/sqflite.dart';

// 筆趣閣型章節頁：#content 內混有隱藏防採集文字、導覽、推薦清單
const _chapterPage = '''
<html><head><meta charset="utf-8"><title>第一章</title></head><body>
<div class="header"><a href="/">首頁</a><a href="/top">排行</a></div>
<div class="wrap">
  <div class="bookname"><h1>第一章 少年</h1>
    <div class="bottem1"><a href="/b/1/">上一章</a> <a href="/b/1/">返回目錄</a> <a href="/b/1/2.html">下一章</a></div>
  </div>
  <div id="content">
    &nbsp;&nbsp;&nbsp;&nbsp;夜幕低垂，寒風刺骨。<br /><br />
    &nbsp;&nbsp;&nbsp;&nbsp;少年緊握長劍，<span>眼神堅定。</span><br /><br />
    <span style="display:none">防採集隱藏字</span>
    　　筆趣閣最新章節請到 www.example.com<br />
    <script>ad()</script>
  </div>
  <ul class="recommend-list"><li><a href="/x">推薦書一</a></li><li><a href="/y">推薦書二</a></li></ul>
  <div class="footer">版權所有</div>
</div></body></html>
''';

void main() {
  onlineServiceTests();
  group('ChapterContentExtractor 正文', () {
    test('挑出 #content、保留段落、去除隱藏字/腳本/浮水印/導覽', () {
      final text = ChapterContentExtractor.extractText(_chapterPage);
      expect(text, '夜幕低垂，寒風刺骨。\n\n少年緊握長劍，眼神堅定。');
    });

    test('自訂 selector 優先；selector 語法錯誤時退回啟發式', () {
      const html = '<div class="a">短</div><div class="b">指定區塊文字</div>';
      expect(ChapterContentExtractor.extractText(html, selector: '.b'), '指定區塊文字');
      expect(ChapterContentExtractor.extractText(html, selector: '[[bad'), isNotEmpty);
    });

    test('正文直接放在 body 下（piaotia 型）：只取正文，不含導覽/工具列/頁尾', () {
      const html = '''
        <html><head><title>t</title></head>
        <div id="guild"><a href="/">飘天文学</a> <a href="./">章节目录</a> <a href="/b">加入书架</a></div>
        <div id="shop"><span>选择背景颜色：</span></div>
        <H1><a href="/info">书名</a> 第二章 再从头</H1>
        <div class="toplink"><a href="1.html">上一章</a> <a href="./">返回目录</a> <a href="3.html">下一章</a></div>
        <table><tr><td><script>ad()</script></td></tr></table>
        <br>&nbsp;&nbsp;&nbsp;&nbsp;第一段正文，楚阳睁开眼睛，只觉得浑身剧痛，四肢百骸仿佛被拆散重组。<br />
        <br />&nbsp;&nbsp;&nbsp;&nbsp;可……这是怎么回事？<br />
        <br />&nbsp;&nbsp;&nbsp;&nbsp;楚阳无语了，望着陌生的屋顶，脑海中一片混乱。<br />
        <div class="bottomlink"><a href="3.html">下一章</a></div>
        <div id="footer">重要声明：小说所有的文字均由网友发表，与本站立场无关。Copyright © 飘天文学</div>
        </html>''';
      expect(ChapterContentExtractor.extractText(html),
          '第一段正文，楚阳睁开眼睛，只觉得浑身剧痛，四肢百骸仿佛被拆散重组。\n\n可……这是怎么回事？\n\n楚阳无语了，望着陌生的屋顶，脑海中一片混乱。');
    });

    test('每段一個 div（hetushu 型）：取整個容器並去除 cite/var 浮水印', () {
      const html = '''
        <div id="cbox"><div id="ctitle"><div class="title">第一章</div></div>
        <div id="content"><h2>第一章</h2>
          <div>第一段文字，夜幕低垂。</div>
          <div>第二段文字，<cite>和_图_书</cite>寒風刺骨。</div>
          <div>第三段<var>https://m.example.com</var>文字。</div>
        </div></div>''';
      expect(ChapterContentExtractor.extractText(html),
          '第一章\n\n第一段文字，夜幕低垂。\n\n第二段文字，寒風刺骨。\n\n第三段文字。');
    });

    test('同章分頁：只接受 123_2.html 這類延伸檔名，不把下一章當下一頁', () {
      const p1 = '<a href="123_2.html">下一頁</a><a href="124.html">下一章</a>';
      expect(ChapterContentExtractor.findNextPageUrl(p1, 'https://s.com/b/123.html'),
          'https://s.com/b/123_2.html');
      const p2 = '<a href="123_3.html">下一页</a>';
      expect(ChapterContentExtractor.findNextPageUrl(p2, 'https://s.com/b/123_2.html'),
          'https://s.com/b/123_3.html');
      const onlyNextChapter = '<a href="124.html">下一页</a>';
      expect(ChapterContentExtractor.findNextPageUrl(onlyNextChapter, 'https://s.com/b/123.html'),
          isNull);
    });
  });

  group('編碼偵測', () {
    test('標頭優先，其次 <meta>，皆無則 null', () {
      final gbkMeta = Uint8List.fromList(latin1.encode('<meta http-equiv="Content-Type" content="text/html; charset=gbk">'));
      expect(detectHtmlCharset(gbkMeta, null), 'gbk');
      expect(detectHtmlCharset(gbkMeta, 'text/html; charset=UTF-8'), 'utf-8');
      expect(detectHtmlCharset(Uint8List.fromList(latin1.encode('<meta charset="GB2312">')), null), 'gb2312');
      expect(detectHtmlCharset(Uint8List.fromList(latin1.encode('<p>x</p>')), null), isNull);
    });
  });

  group('WebCatalogResolver 目錄', () {
    test('「最新章節」區塊重複時保留正文順序', () {
      const html = '''
        <div id="list"><dl>
          <dt>最新章節</dt>
          <dd><a href="3.html">第三章 終</a></dd>
          <dt>正文</dt>
          <dd><a href="1.html">第一章 始</a></dd>
          <dd><a href="2.html">第二章 中</a></dd>
          <dd><a href="3.html">第三章 終</a></dd>
        </dl></div>''';
      final r = WebCatalogResolver.instance
          .resolve(bookId: 'b', rawUrl: 'https://s.com/b/', htmlContent: html, customSelector: '#list dd a');
      expect(r.chapters.map((c) => c.title), ['第一章 始', '第二章 中', '第三章 終']);
      expect(r.chapters.map((c) => c.chapterIndex), [0, 1, 2]);
    });

    test('啟發式不會選到含導覽連結的外層容器', () {
      final chapters = List.generate(6, (i) => '<li><a href="c$i.html">第${i + 1}章 標題</a></li>').join();
      final html = '''
        <div id="wrap">
          <div class="nav"><a href="/a">玄幻</a><a href="/b">武俠</a><a href="/c">都市</a></div>
          <ul class="chapters">$chapters</ul>
        </div>''';
      final r = WebCatalogResolver.instance.resolve(bookId: 'b', rawUrl: 'https://s.com/', htmlContent: html);
      expect(r.chapters.length, 6);
      expect(r.chapters.any((c) => c.title == '玄幻'), isFalse);
    });

    test('書籍頁 → 完整目錄 → 下一頁 / <select> 分頁，全部合併並重新編號', () async {
      String list(List<int> ns) => ns.map((n) => '<li><a href="/b/$n.html">第$n章 標題</a></li>').join();
      final pages = {
        'https://s.com/b/': '<h1>書名</h1><a href="/b/all.html">查看完整目錄</a><ul>${list([9, 8])}</ul>',
        'https://s.com/b/all.html': '<ul class="chapter">${list([1, 2, 3, 4, 5])}</ul><a href="/b/all_2.html">下一頁</a>',
        'https://s.com/b/all_2.html':
            '<ul class="chapter">${list([6, 7, 8, 9, 10])}</ul>'
                '<select><option value="/b/all.html">1</option><option value="/b/all_2.html" selected>2</option>'
                '<option value="/b/all_3.html">3</option></select>',
        'https://s.com/b/all_3.html': '<ul class="chapter">${list([11, 12, 13, 14, 15])}</ul>',
      };
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        final body = pages[req.url.toString()];
        return body == null ? http.Response('', 404) : http.Response.bytes(utf8.encode(body), 200);
      });
      final info = await WebCatalogResolver.instance
          .fetchBookInfoAndCatalog(rawUrl: 'https://s.com/b/', bookId: 'b', client: client);
      expect(info.chapters.map((c) => c.title), [for (var n = 1; n <= 15; n++) '第$n章 標題']);
      expect(info.chapters.last.chapterIndex, 14);
      expect(requested.toSet().length, requested.length, reason: '同頁不重複下載');
    });

    test('分頁中途斷線：保留已取得章節而不是整本失敗', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/b/') {
          return http.Response.bytes(
              utf8.encode('<ul>${List.generate(5, (i) => '<li><a href="/b/$i.html">第$i章</a></li>').join()}</ul><a href="/b/p2">下一頁</a>'),
              200);
        }
        throw http.ClientException('offline');
      });
      final info = await WebCatalogResolver.instance
          .fetchBookInfoAndCatalog(rawUrl: 'https://s.com/b/', bookId: 'b', client: client);
      expect(info.chapters.length, 5);
    });
  });
}

class _FakeDb extends Fake implements Database {
  _FakeDb([this.row]);
  final Map<String, Object?>? row;
  final updates = <String>[];
  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
          String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
      row == null ? [] : [row!];
  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    updates.add(values['content'] as String);
    return 1;
  }
}

void onlineServiceTests() {
  group('OnlineChapterService 同章分頁', () {
    const base = 'https://s.com/b/5.html';
    final pages = {
      base: '<div id="content">第一頁內容。</div><a href="5_2.html">下一頁</a><a href="6.html">下一章</a>',
      'https://s.com/b/5_2.html': '<div id="content">第二頁內容。</div><a href="6.html">下一章</a>',
    };

    test('合併所有分頁並寫入快取', () async {
      final db = _FakeDb();
      final text = await OnlineChapterService(db: db).getChapterText(
          bookId: 'b', chapterIndex: 0, chapterUrl: base, fetcher: (u) async => pages[u]!);
      expect(text, '第一頁內容。\n\n第二頁內容。');
      expect(db.updates, [text]);
    });

    test('第二頁斷線：回傳已取得內容但不寫快取，下次可重抓', () async {
      final db = _FakeDb();
      final text = await OnlineChapterService(db: db).getChapterText(
          bookId: 'b',
          chapterIndex: 0,
          chapterUrl: base,
          fetcher: (u) async => u == base ? pages[u]! : throw http.ClientException('offline'));
      expect(text, '第一頁內容。');
      expect(db.updates, isEmpty);
    });

    test('未傳網址時改用目錄存的 chapterUrl（ReaderView 的 ChapterMarker 沒有網址）', () async {
      final fetched = <String>[];
      final text = await OnlineChapterService(db: _FakeDb({'content': null, 'chapterUrl': base}))
          .getChapterText(bookId: 'b', chapterIndex: 0, chapterUrl: '', fetcher: (u) async {
        fetched.add(u);
        return pages[u]!;
      });
      expect(fetched.first, base);
      expect(text, contains('第一頁內容。'));
      final none = await OnlineChapterService(db: _FakeDb())
          .getChapterText(bookId: 'b', chapterIndex: 0, chapterUrl: '', fetcher: (_) async => fail('不應發出請求'));
      expect(none, contains('沒有來源網址'));
    });

    test('完全斷線：回傳錯誤提示且不寫快取', () async {
      final db = _FakeDb();
      final text = await OnlineChapterService(db: db).getChapterText(
          bookId: 'b', chapterIndex: 0, chapterUrl: base, fetcher: (_) async => throw http.ClientException('x'));
      expect(text, contains('網路連線失敗'));
      expect(db.updates, isEmpty);
    });
  });
}
