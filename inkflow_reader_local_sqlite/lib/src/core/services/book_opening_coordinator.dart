import 'app_logger.dart';
import '../models/site_rule.dart';
import '../models/chapter_cache_entry.dart';
import '../crawler/crawler_state.dart';
import 'chapter_aggregation_pipeline.dart';
import 'database_service.dart';

enum BookPreparationResultStatus {
  cachedReady,
  preloadedSuccess,
  failed,
}

class BookPreparationResult {
  final BookPreparationResultStatus status;
  final ChapterCacheEntry? firstChapter;
  final CrawlerError? error;

  BookPreparationResult({
    required this.status,
    this.firstChapter,
    this.error,
  });
}

class BookOpeningCoordinator {
  final DatabaseService dbService;
  final ChapterAggregationPipeline pipeline;

  BookOpeningCoordinator({
    required this.dbService,
    required this.pipeline,
  });

  /// 準備開啟書籍：若本機無快取，自動啟動無頭爬蟲預載 3 頁
  Future<BookPreparationResult> prepareBookForReading({
    required String bookId,
    required String bookHomeUrl,
  }) async {
    AppLogger.reader('正在檢查書籍快取: bookId=$bookId, url=$bookHomeUrl');

    // 1. 檢查本機第 1 章是否已快取
    final cachedChapter = await dbService.getChapter(bookId, 1);
    if (cachedChapter != null && cachedChapter.content.trim().isNotEmpty) {
      AppLogger.reader('命中本機快取，直接開啟第一章: ${cachedChapter.title}');
      return BookPreparationResult(
        status: BookPreparationResultStatus.cachedReady,
        firstChapter: cachedChapter,
      );
    }

    // 2. 本機無快取，啟動背景預載管線抓取前 3 頁
    AppLogger.crawler('本機無快取，開始執行背景無頭爬蟲預載 (3 頁)...');
    final rule = SiteRule.findRuleForUrl(bookHomeUrl);
    AppLogger.crawler('匹配書源規則: ${rule.name}');

    try {
      final entries = await pipeline.fetchInitialPages(
        bookId: bookId,
        bookHomeUrl: bookHomeUrl,
        rule: rule,
        initialPages: 3,
      );

      if (entries.isEmpty) {
        throw CrawlerError(
          failedUrl: bookHomeUrl,
          message: '未能成功抓取到任何章節內容',
          type: CrawlerErrorType.elementNotFound,
        );
      }

      AppLogger.crawler('預載成功，共寫入 ${entries.length} 筆章節紀錄至本機');
      return BookPreparationResult(
        status: BookPreparationResultStatus.preloadedSuccess,
        firstChapter: entries.first,
      );
    } on CrawlerError catch (e) {
      AppLogger.error('預載爬蟲中斷: ${e.message}', e);
      return BookPreparationResult(
        status: BookPreparationResultStatus.failed,
        error: e,
      );
    } catch (e, stack) {
      AppLogger.error('未預期的異常: $e', e, stack);
      return BookPreparationResult(
        status: BookPreparationResultStatus.failed,
        error: CrawlerError(
          failedUrl: bookHomeUrl,
          message: e.toString(),
          type: CrawlerErrorType.unknown,
        ),
      );
    }
  }
}
