import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/chapter_cache_entry.dart';
import '../../../lib/src/core/services/database_service.dart';

void main() {
  group('Database Schema & Model Migration Tests', () {
    test('ChapterCacheEntry 應正確序列化與反序列化 source_url 與 is_merged', () {
      final entry = ChapterCacheEntry(
        id: 1,
        bookId: 'book_test_1',
        chapterIndex: 1,
        title: '第一章 測試起點',
        content: '這是第一章正文。',
        sourceUrl: 'https://example.com/book/1.html',
        updatedAt: 1696500000000,
        isMerged: true,
      );

      final map = entry.toMap();
      expect(map['source_url'], equals('https://example.com/book/1.html'));
      expect(map['is_merged'], equals(1));

      final restored = ChapterCacheEntry.fromMap(map);
      expect(restored.id, equals(1));
      expect(restored.sourceUrl, equals('https://example.com/book/1.html'));
      expect(restored.isMerged, isTrue);
      expect(restored.title, equals('第一章 測試起點'));
    });

    test('ChapterCacheEntry 支援 copyWith 更新來源網址與合併狀態', () {
      final entry = ChapterCacheEntry(
        bookId: 'book_test_1',
        chapterIndex: 1,
        title: '第一章 測試起點',
        content: '第一頁內容。',
        sourceUrl: 'https://example.com/book/1_1.html',
        updatedAt: 1000,
        isMerged: false,
      );

      final updated = entry.copyWith(
        content: '${entry.content}\n\n第二頁接續內容。',
        sourceUrl: 'https://example.com/book/1_2.html',
        isMerged: true,
      );

      expect(updated.content, contains('第二頁接續內容。'));
      expect(updated.sourceUrl, equals('https://example.com/book/1_2.html'));
      expect(updated.isMerged, isTrue);
    });

    test('DatabaseService 定義之資料表結構與升級版本確認', () {
      expect(DatabaseService.dbVersion, equals(2));
      expect(DatabaseService.tableChapters, equals('chapters'));
      expect(DatabaseService.createTableQuery, contains('source_url TEXT NOT NULL'));
      expect(DatabaseService.createTableQuery, contains('is_merged INTEGER DEFAULT 0'));
    });
  });
}
