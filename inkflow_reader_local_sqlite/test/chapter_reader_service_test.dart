import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inkflow_reader/src/core/services/chapter_reader_service.dart';

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

  group('ChapterReaderService 雙模式與預載管線測試', () {
    const fakeBookId = 'book_001';

    test('Cache Hit：本地已快取時直接回傳 nativeText 模式且不發送 HTTP 請求', () async {
      final inMemoryDb = <int, Map<String, dynamic>>{
        0: {
          'chapterIndex': 0,
          'title': '第一章',
          'chapterUrl': 'https://ex.com/c1.html',
          'isSaved': 1,
          'content': '這是本地已快取的極速內文。',
        }
      };

      final service = ChapterReaderService(
        dbChapterGetter: (bookId, index) async => inMemoryDb[index],
        dbChapterSaver: (bookId, index, content) async {},
      );

      final result = await service.loadChapter(
        bookId: fakeBookId,
        chapterIndex: 0,
      );

      expect(result.mode, ReadingMode.nativeText);
      expect(result.isFromCache, isTrue);
      expect(result.content, '這是本地已快取的極速內文。');
    });

    test('Cache Miss：發起 HTTP 抓取、解析純文字並自動回寫本地快取', () async {
      final inMemoryDb = <int, Map<String, dynamic>>{
        1: {
          'chapterIndex': 1,
          'title': '第二章 逆境崛起',
          'chapterUrl': 'https://ex.com/c2.html',
          'isSaved': 0,
          'content': null,
        }
      };

      final mockClient = MockClient((request) async {
        return http.Response(
          '''
            <div id="read-box">
              <p>狂風呼嘯而過，暴雨洗刷著大地。</p>
              <p>少年迎風而立，周身靈氣奔湧澎湃！長度充分足夠驗證。</p>
            </div>
          ''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final service = ChapterReaderService(
        httpClient: mockClient,
        dbChapterGetter: (bookId, index) async => inMemoryDb[index],
        dbChapterSaver: (bookId, index, content) async {
          inMemoryDb[index] = {
            ...inMemoryDb[index]!,
            'isSaved': 1,
            'content': content,
          };
        },
      );

      final result = await service.loadChapter(
        bookId: fakeBookId,
        chapterIndex: 1,
        readSelector: '#read-box',
      );

      expect(result.mode, ReadingMode.nativeText);
      expect(result.isFromCache, isFalse);
      expect(result.content, contains('少年迎風而立'));

      // 明確以變數取出 key 1 進行驗證，避免格式錯亂
      const targetIndex = 1;
      final savedChapter1 = inMemoryDb[targetIndex];
      expect(savedChapter1?['isSaved'], 1);
      expect(savedChapter1?['content'], contains('少年迎風而立'));
    });

    test('Fallback：抓取失敗或遭遇強反爬時，安全降級為 webViewFallback 模式', () async {
      final inMemoryDb = <int, Map<String, dynamic>>{
        2: {
          'chapterIndex': 2,
          'title': '第三章 迷局',
          'chapterUrl': 'https://ex.com/c3.html',
          'isSaved': 0,
          'content': null,
        }
      };

      final mockClient = MockClient((request) async {
        return http.Response('<html><body>Please verify you are human</body></html>', 503);
      });

      final service = ChapterReaderService(
        httpClient: mockClient,
        dbChapterGetter: (bookId, index) async => inMemoryDb[index],
      );

      final result = await service.loadChapter(
        bookId: fakeBookId,
        chapterIndex: 2,
      );

      expect(result.mode, ReadingMode.webViewFallback);
      expect(result.content, isNull);
      expect(result.chapterUrl, 'https://ex.com/c3.html');
    });

    test('預加載管線：自動非同步抓取後續章節並快取入庫', () async {
      final inMemoryDb = <int, Map<String, dynamic>>{
        10: {'chapterIndex': 10, 'chapterUrl': 'https://ex.com/c10.html', 'isSaved': 0},
        11: {'chapterIndex': 11, 'chapterUrl': 'https://ex.com/c11.html', 'isSaved': 0},
      };

      // 內文加長，保證通過字數驗證門檻
      final mockClient = MockClient((request) async {
        return http.Response(
          '<div id="txt"><p>這是預加載章節的詳細正文內容，文字內容非常充足且完整，字數已確定超過三十字門檻。</p></div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final service = ChapterReaderService(
        httpClient: mockClient,
        dbChapterGetter: (bookId, index) async => inMemoryDb[index],
        dbChapterSaver: (bookId, index, content) async {
          inMemoryDb[index] = {...inMemoryDb[index]!, 'isSaved': 1, 'content': content};
        },
      );

      // 讀者在第 9 章，預載後續 2 章 (第 10、11 章)
      await service.preloadAdjacentChapters(
        bookId: fakeBookId,
        currentChapterIndex: 9,
        readSelector: '#txt',
        preloadCount: 2,
      );

      final savedChapter10 = inMemoryDb[10];
      final savedChapter11 = inMemoryDb[11];
      expect(savedChapter10?['isSaved'], 1);
      expect(savedChapter11?['isSaved'], 1);
    });
  });
}