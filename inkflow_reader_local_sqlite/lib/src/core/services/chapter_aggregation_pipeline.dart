import 'dart:async';
import '../models/site_rule.dart';
import '../models/chapter_cache_entry.dart';
import '../crawler/crawler_state.dart';
import '../crawler/headless_crawler_service.dart';
import 'content_sanitizer.dart';
import 'database_service.dart';

abstract class IChapterStorage {
  Future<void> saveChapter(ChapterCacheEntry entry);
  Future<ChapterCacheEntry?> getChapter(String bookId, int chapterIndex);
}

class DatabaseChapterStorage implements IChapterStorage {
  final DatabaseService dbService;
  DatabaseChapterStorage(this.dbService);

  @override
  Future<void> saveChapter(ChapterCacheEntry entry) => dbService.saveChapter(entry);

  @override
  Future<ChapterCacheEntry?> getChapter(String bookId, int chapterIndex) =>
      dbService.getChapter(bookId, chapterIndex);
}

class ChapterAggregationPipeline {
  final HeadlessCrawlerService crawler;
  final IChapterStorage storage;

  ChapterAggregationPipeline({
    required this.crawler,
    required this.storage,
  });

  /// 初始預載：開啟小說時，預設連續載入 3 頁
  Future<List<ChapterCacheEntry>> fetchInitialPages({
    required String bookId,
    required String bookHomeUrl,
    required SiteRule rule,
    int initialPages = 3,
  }) async {
    final List<ChapterCacheEntry> savedEntries = [];

    // 1. 點擊「開始閱讀」抓取首頁
    final firstPage = await crawler.startReadingFromBookHome(
      bookHomeUrl: bookHomeUrl,
      rule: rule,
    );

    var currentChapterIndex = 1;
    var currentEntry = ChapterCacheEntry(
      bookId: bookId,
      chapterIndex: currentChapterIndex,
      title: firstPage.title,
      content: ContentSanitizer.sanitize(firstPage.rawContent),
      sourceUrl: firstPage.url,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      isMerged: false,
    );

    await storage.saveChapter(currentEntry);
    savedEntries.add(currentEntry);

    // 2. 依序快取後續分頁 (若 initialPages > 1)
    for (int i = 1; i < initialPages; i++) {
      if (!firstPage.hasNextPage && crawler.status != CrawlerStatus.success) break;

      final nextPage = await crawler.navigateToNextPage(rule: rule);
      final sanitizedContent = ContentSanitizer.sanitize(nextPage.rawContent);

      if (isContinuationPage(currentEntry.title, nextPage.title, nextPage.isNextChapter)) {
        // 同一章節接續段落：拼接正文並更新網址
        currentEntry = currentEntry.copyWith(
          content: '${currentEntry.content}\n\n$sanitizedContent',
          sourceUrl: nextPage.url,
          isMerged: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await storage.saveChapter(currentEntry);
        // 更新清單中的當前項目
        savedEntries[savedEntries.length - 1] = currentEntry;
      } else {
        // 全新章節
        currentChapterIndex++;
        currentEntry = ChapterCacheEntry(
          bookId: bookId,
          chapterIndex: currentChapterIndex,
          title: nextPage.title,
          content: sanitizedContent,
          sourceUrl: nextPage.url,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          isMerged: false,
        );
        await storage.saveChapter(currentEntry);
        savedEntries.add(currentEntry);
      }
    }

    return savedEntries;
  }

  /// 隨讀隨載：當原生閱讀器翻到末端時推進下一頁
  Future<ChapterCacheEntry> fetchNextPage({
    required String bookId,
    required int currentChapterIndex,
    required SiteRule rule,
  }) async {
    final nextPage = await crawler.navigateToNextPage(rule: rule);
    final sanitizedContent = ContentSanitizer.sanitize(nextPage.rawContent);
    final currentEntry = await storage.getChapter(bookId, currentChapterIndex);

    if (currentEntry != null &&
        isContinuationPage(currentEntry.title, nextPage.title, nextPage.isNextChapter)) {
      final mergedEntry = currentEntry.copyWith(
        content: '${currentEntry.content}\n\n$sanitizedContent',
        sourceUrl: nextPage.url,
        isMerged: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await storage.saveChapter(mergedEntry);
      return mergedEntry;
    } else {
      final newIndex = currentChapterIndex + 1;
      final newEntry = ChapterCacheEntry(
        bookId: bookId,
        chapterIndex: newIndex,
        title: nextPage.title,
        content: sanitizedContent,
        sourceUrl: nextPage.url,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isMerged: false,
      );
      await storage.saveChapter(newEntry);
      return newEntry;
    }
  }

  /// 判斷是否為同章節接續段落
  bool isContinuationPage(String previousTitle, String currentTitle, bool isNextChapterFlag) {
    if (isNextChapterFlag) return false;

    // 清理括號中的分頁後綴如 (1/2), （上）, (2)
    final cleanPrev = previousTitle.replaceAll(RegExp(r'[\(\[\（].*?[\)\]\）]'), '').trim();
    final cleanCurr = currentTitle.replaceAll(RegExp(r'[\(\[\（].*?[\)\]\）]'), '').trim();

    if (cleanPrev.isNotEmpty && cleanCurr.isNotEmpty && cleanPrev == cleanCurr) {
      return true;
    }

    if (RegExp(r'\([0-9]+/[0-9]+\)|（[0-9]+/[0-9]+）|\([0-9]+\)|（[0-9]+）').hasMatch(currentTitle)) {
      return true;
    }

    return false;
  }
}
