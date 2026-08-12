import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/library_database.dart';
import 'package:inkflow_reader/src/core/services/web_chapter_downloader.dart';
import 'package:inkflow_reader/src/features/library/book.dart';
import 'package:inkflow_reader/src/features/library/web_novel_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LibraryDatabase database;
  late WebChapterDownloader downloader;
  setUp(() {
    database = LibraryDatabase(databaseFactory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    downloader = WebChapterDownloader(database: database, minimumCharacters: 20);
  });
  tearDown(() => database.close());

  test('extracts dense content and removes repeated title', () {
    final result = downloader.extract('''<html><body><nav>返回目錄</nav><article>
      <h1>第 1 章 開始</h1><p>第一段有足夠的正文內容。</p><p>第二段繼續故事而不是導覽文字。</p>
    </article></body></html>''', pageUrl: Uri.parse('https://example.com/book/1'), chapterTitle: '第 1 章 開始');
    expect(result.content, contains('第一段'));
    expect(result.content, isNot(contains('返回目錄')));
  });

  test('merges pages without duplicate boundary paragraph', () {
    expect(WebChapterDownloader.mergePages(['甲\n\n乙', '乙\n\n丙']), '甲\n\n乙\n\n丙');
  });

  test('serializes concurrent requests and reuses the completed chapter', () async {
    final book = Book(
      id: 'book-1',
      title: '測試書',
      author: '作者',
      sourceType: BookSourceType.web,
      characterOffset: 0,
      currentChapter: '',
      progressRatio: 0,
      createdAt: DateTime(2026),
      isFinished: false,
    );
    await database.insertBook(
      book,
      webChapters: [
        WebChapter(
          url: 'https://example.com/chapter-1',
          normalizedUrl: 'https://example.com/chapter-1',
          title: '第一章',
          position: 0,
        ),
      ],
    );
    final chapter = (await database.loadWebChapters(book.id)).single;
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response(
        '<html><body><article>第一段有足夠的正文內容。第二段繼續故事，確保解析器可以接受。</article></body></html>',
        200,
      );
    });
    final first = WebChapterDownloader(
      database: database,
      client: client,
      minimumCharacters: 20,
    );
    final second = WebChapterDownloader(
      database: database,
      client: client,
      minimumCharacters: 20,
    );

    final results = await Future.wait([
      first.download(chapter),
      second.download(chapter),
    ]);

    expect(results.map((result) => result.status), everyElement(WebChapterStatus.complete));
    expect(requestCount, 1);
  });
}
