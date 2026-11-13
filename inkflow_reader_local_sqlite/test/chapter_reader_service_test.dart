import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inkflow_reader/src/core/services/chapter_reader_service.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  group('ChapterContentExtractor 正文抽取測試', () {
    test('透過 Selector 正確抽取正文並將 <br> 轉換為適當段落換行', () {
      const mockHtml = '''
        <html>
          <body>
            <div class="ad">廣告內容請忽略</div>
            <div id="content">
              第一行內文。<br/>
              第二行內文。<br><br>
              第三行內文。
            </div>
          </body>
        </html>
      ''';

      final text = ChapterContentExtractor.extractText(mockHtml, selector: '#content');
      expect(text, contains('第一行內文。'));
      expect(text, contains('第二行內文。'));
      expect(text, contains('第三行內文。'));
      expect(text, isNot(contains('廣告內容')));
    });

    test('無 Selector 時能夠啟發式辨識段落最多之容器並忽略導航雜訊', () {
      const mockHtml = '''
        <html>
          <body>
            <nav><p>導航選單</p></nav>
            <article>
              <p>天色微涼，少年緩緩睜開雙眼。</p>
              <p>他望向遠處蒼茫的山脈，心中充滿了堅毅。</p>
              <p>這一次，他絕不再退縮！</p>
            </article>
          </body>
        </html>
      ''';

      final text = ChapterContentExtractor.extractText(mockHtml);
      expect(text, contains('天色微涼，少年緩緩睜開雙眼。'));
      expect(text, contains('這一次，他絕不再退縮！'));
    });
  });

  // 依目前 API 改寫：服務改為單例 + setDatabase(sqflite)，下載走 package:http 頂層函式；
  // 舊版的 dbChapterGetter/httpClient 注入、webViewFallback 與 preloadAdjacentChapters 已移除。
  group('ChapterReaderService 快取與降級', () {
    final service = ChapterReaderService.instance;
    final longText = '這是本地已快取的極速內文。' * 10; // >= 80 字才算快取命中

    test('Cache Hit：快取內容足夠時直接回傳且不發送 HTTP', () async {
      final db = _FakeDb({'content': longText});
      service.setDatabase(db);
      var requests = 0;
      final result = await http.runWithClient(
        () => service.loadChapter(bookId: 'b', chapterIndex: 0, url: 'https://ex.com/c1.html'),
        () => MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      expect(result.isFromCache, isTrue);
      expect(result.mode, ReadingMode.nativeText);
      expect(result.content, longText);
      expect(requests, 0);
    });

    test('Cache Miss：抓取解析後寫回快取', () async {
      final db = _FakeDb(null);
      service.setDatabase(db);
      final body = '<div id="read-box"><p>少年迎風而立，周身靈氣奔湧澎湃！</p>'
          '<p>${'狂風呼嘯而過，暴雨洗刷著大地。' * 6}</p></div>';
      final result = await http.runWithClient(
        () => service.loadChapter(bookId: 'b', chapterIndex: 1, url: 'https://ex.com/c2.html'),
        () => MockClient((_) async => http.Response.bytes(utf8.encode(body), 200)),
      );
      expect(result.isFromCache, isFalse);
      expect(result.content, contains('少年迎風而立'));
      expect(db.inserted?['content'], contains('少年迎風而立'));
      expect(db.inserted?['chapterIndex'], 1);
    });

    test('抓取失敗但有舊快取：降級回傳舊快取', () async {
      service.setDatabase(_FakeDb({'content': '短的舊快取'}));
      final result = await http.runWithClient(
        () => service.loadChapter(bookId: 'b', chapterIndex: 2, url: 'https://ex.com/c3.html'),
        () => MockClient((_) async => http.Response('verify you are human', 503)),
      );
      expect(result.isFromCache, isTrue);
      expect(result.content, '短的舊快取');
    });

    test('抓取失敗且無快取：拋出例外交由呼叫端處理', () async {
      service.setDatabase(_FakeDb(null));
      await expectLater(
        http.runWithClient(
          () => service.loadChapter(bookId: 'b', chapterIndex: 3, url: 'https://ex.com/c4.html'),
          () => MockClient((_) async => http.Response('', 503)),
        ),
        throwsException,
      );
    });
  });
}

class _FakeDb extends Fake implements Database {
  _FakeDb(this.row);
  final Map<String, Object?>? row;
  Map<String, Object?>? inserted;

  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
          String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
      row == null ? [] : [row!];

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    inserted = values;
    return 1;
  }
}
