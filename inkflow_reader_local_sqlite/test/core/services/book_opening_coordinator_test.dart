import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/site_rule.dart';
import '../../../lib/src/core/models/chapter_cache_entry.dart';
import '../../../lib/src/core/crawler/crawler_state.dart';
import '../../../lib/src/core/crawler/web_crawler_driver.dart';
import '../../../lib/src/core/crawler/headless_crawler_service.dart';
import '../../../lib/src/core/services/chapter_aggregation_pipeline.dart';
import '../../../lib/src/core/services/database_service.dart';
import '../../../lib/src/core/services/book_opening_coordinator.dart';

class InMemoryDatabaseService extends DatabaseService {
  final Map<String, ChapterCacheEntry> memoryStore = {};

  @override
  Future<void> saveChapter(ChapterCacheEntry entry) async {
    memoryStore['${entry.bookId}_${entry.chapterIndex}'] = entry;
  }

  @override
  Future<ChapterCacheEntry?> getChapter(String bookId, int chapterIndex) async {
    return memoryStore['${bookId}_$chapterIndex'];
  }
}

class FakeWebDriver implements WebCrawlerDriver {
  @override
  Future<void> loadUrl(String url) async {}

  @override
  Future<dynamic> evaluateJavascript(String script) async {
    if (script.contains('開始閱讀')) return true;
    if (script.contains('titleEl')) {
      return {
        'url': 'https://czbooks.net/n/skg2jdampkp/1',
        'title': '第一章 穿越',
        'content': '正文內容開始...',
        'hasNext': true,
        'isNextChapter': false,
      };
    }
    if (script.contains('nextEl')) return true;
    return null;
  }

  @override
  Future<String?> getCurrentUrl() async => 'https://czbooks.net/n/skg2jdampkp/1';

  @override
  Future<void> dispose() async {}
}

void main() {
  group('BookOpeningCoordinator Tests', () {
    test('無快取時自動觸發預載，不再丟出「章節 URL 為空」例外', () async {
      final db = InMemoryDatabaseService();
      final crawler = HeadlessCrawlerService(driver: FakeWebDriver());
      final pipeline = ChapterAggregationPipeline(
        crawler: crawler,
        storage: DatabaseChapterStorage(db),
      );
      final coordinator = BookOpeningCoordinator(
        dbService: db,
        pipeline: pipeline,
      );

      final result = await coordinator.prepareBookForReading(
        bookId: 'book_cz_1',
        bookHomeUrl: 'https://czbooks.net/n/skg2jdampkp',
      );

      expect(result.status, equals(BookPreparationResultStatus.preloadedSuccess));
      expect(result.firstChapter, isNotNull);
      expect(result.firstChapter!.title, equals('第一章 穿越'));
      expect(result.firstChapter!.sourceUrl, contains('czbooks.net'));
    });
  });
}
