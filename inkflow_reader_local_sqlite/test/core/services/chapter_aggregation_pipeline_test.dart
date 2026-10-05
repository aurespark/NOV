import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/site_rule.dart';
import '../../../lib/src/core/models/chapter_cache_entry.dart';
import '../../../lib/src/core/crawler/web_crawler_driver.dart';
import '../../../lib/src/core/crawler/headless_crawler_service.dart';
import '../../../lib/src/core/services/chapter_aggregation_pipeline.dart';

class MockChapterStorage implements IChapterStorage {
  final Map<String, ChapterCacheEntry> data = {};

  @override
  Future<void> saveChapter(ChapterCacheEntry entry) async {
    data['${entry.bookId}_${entry.chapterIndex}'] = entry;
  }

  @override
  Future<ChapterCacheEntry?> getChapter(String bookId, int chapterIndex) async {
    return data['${bookId}_$chapterIndex'];
  }
}

class PipelineMockDriver implements WebCrawlerDriver {
  int pageCallCount = 0;

  @override
  Future<void> loadUrl(String url) async {}

  @override
  Future<dynamic> evaluateJavascript(String script) async {
    if (script.contains('開始閱讀')) return true;

    if (script.contains('titleEl')) {
      pageCallCount++;
      if (pageCallCount == 1) {
        return {
          'url': 'https://novel.test/book/1/1_1.html',
          'title': '第一章 啟程 (1/2)',
          'content': '這是第一章前半段。',
          'hasNext': true,
          'isNextChapter': false,
        };
      } else if (pageCallCount == 2) {
        return {
          'url': 'https://novel.test/book/1/1_2.html',
          'title': '第一章 啟程 (2/2)',
          'content': '這是第一章後半段接續。',
          'hasNext': true,
          'isNextChapter': false,
        };
      } else {
        return {
          'url': 'https://novel.test/book/1/2.html',
          'title': '第二章 探索新世界',
          'content': '第二章全新的內文。',
          'hasNext': true,
          'isNextChapter': true,
        };
      }
    }

    if (script.contains('nextEl')) return true;
    return null;
  }

  @override
  Future<String?> getCurrentUrl() async => 'https://novel.test/current.html';

  @override
  Future<void> dispose() async {}
}

void main() {
  group('ChapterAggregationPipeline Tests', () {
    late PipelineMockDriver mockDriver;
    late HeadlessCrawlerService crawlerService;
    late MockChapterStorage mockStorage;
    late ChapterAggregationPipeline pipeline;
    final rule = SiteRule.defaultRule();

    setUp(() {
      mockDriver = PipelineMockDriver();
      crawlerService = HeadlessCrawlerService(driver: mockDriver);
      mockStorage = MockChapterStorage();
      pipeline = ChapterAggregationPipeline(
        crawler: crawlerService,
        storage: mockStorage,
      );
    });

    test('初始預載 3 頁並將同章分頁合併寫入資料庫', () async {
      final entries = await pipeline.fetchInitialPages(
        bookId: 'book_001',
        bookHomeUrl: 'https://novel.test/book/1',
        rule: rule,
        initialPages: 3,
      );

      // 前兩頁合併為第 1 章，第三頁為第 2 章，共產出 2 筆章節紀錄
      expect(entries.length, equals(2));

      // 檢查第一章（同章合併成果）
      final ch1 = entries[0];
      expect(ch1.chapterIndex, equals(1));
      expect(ch1.isMerged, isTrue);
      expect(ch1.content, contains('這是第一章前半段。'));
      expect(ch1.content, contains('這是第一章後半段接續。'));
      expect(ch1.sourceUrl, equals('https://novel.test/book/1/1_2.html'));

      // 檢查第二章
      final ch2 = entries[1];
      expect(ch2.chapterIndex, equals(2));
      expect(ch2.title, equals('第二章 探索新世界'));
      expect(ch2.content, contains('第二章全新的內文。'));
    });
  });
}
