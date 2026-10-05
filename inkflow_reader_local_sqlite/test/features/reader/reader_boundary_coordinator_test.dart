import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/chapter_cache_entry.dart';
import '../../../lib/src/core/crawler/crawler_state.dart';
import '../../../lib/src/features/reader/reader_boundary_coordinator.dart';

void main() {
  group('ReaderBoundaryCoordinator Tests', () {
    test('未達末頁時不觸發加載', () async {
      int callCount = 0;
      final coordinator = ReaderBoundaryCoordinator(
        onFetchNext: () async {
          callCount++;
          return ChapterCacheEntry(
            bookId: 'b1',
            chapterIndex: 1,
            title: 't',
            content: 'c',
            sourceUrl: 'u',
            updatedAt: 0,
          );
        },
      );

      // 當前第 2 頁，共 5 頁 -> 未達末頁
      await coordinator.onPageChanged(currentPageIndex: 1, totalPagesInChapter: 5);
      expect(callCount, equals(0));
    });

    test('抵達末頁時觸發下一頁快取', () async {
      int callCount = 0;
      final coordinator = ReaderBoundaryCoordinator(
        onFetchNext: () async {
          callCount++;
          return ChapterCacheEntry(
            bookId: 'b1',
            chapterIndex: 2,
            title: 't2',
            content: 'c2',
            sourceUrl: 'u2',
            updatedAt: 0,
          );
        },
      );

      // 當前第 5 頁 (index 4)，共 5 頁 -> 抵達末頁
      await coordinator.onPageChanged(currentPageIndex: 4, totalPagesInChapter: 5);
      expect(callCount, equals(1));
    });

    test('爬蟲失敗時觸發 onError 並包含出錯網址', () async {
      CrawlerError? caughtError;
      final coordinator = ReaderBoundaryCoordinator(
        onFetchNext: () async {
          throw CrawlerError(
            failedUrl: 'https://novel.test/fail.html',
            message: '找不到章節內容',
            type: CrawlerErrorType.elementNotFound,
          );
        },
        onError: (err) {
          caughtError = err;
        },
      );

      await coordinator.onPageChanged(currentPageIndex: 0, totalPagesInChapter: 1);

      expect(caughtError, isNotNull);
      expect(caughtError!.failedUrl, equals('https://novel.test/fail.html'));
      expect(caughtError!.type, equals(CrawlerErrorType.elementNotFound));
    });
  });
}
