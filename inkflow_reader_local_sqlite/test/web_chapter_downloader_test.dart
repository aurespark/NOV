import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/library_database.dart';
import 'package:inkflow_reader/src/core/services/web_chapter_downloader.dart';
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
}
