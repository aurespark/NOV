import 'dart:async';
import '../../core/models/chapter_cache_entry.dart';
import '../../core/crawler/crawler_state.dart';

class ReaderBoundaryCoordinator {
  final Future<ChapterCacheEntry> Function() onFetchNext;
  final void Function(CrawlerError error)? onError;
  final void Function(ChapterCacheEntry entry)? onChapterUpdated;

  bool _isFetching = false;
  bool get isFetching => _isFetching;

  ReaderBoundaryCoordinator({
    required this.onFetchNext,
    this.onError,
    this.onChapterUpdated,
  });

  /// 監聽原生閱讀器翻頁動作：當翻至章節末頁時觸發
  Future<void> onPageChanged({
    required int currentPageIndex,
    required int totalPagesInChapter,
  }) async {
    if (currentPageIndex >= totalPagesInChapter - 1) {
      if (_isFetching) return;
      _isFetching = true;

      try {
        final result = await onFetchNext();
        onChapterUpdated?.call(result);
      } catch (e) {
        if (e is CrawlerError) {
          onError?.call(e);
        } else {
          onError?.call(
            CrawlerError(
              failedUrl: '',
              message: e.toString(),
              type: CrawlerErrorType.unknown,
            ),
          );
        }
      } finally {
        _isFetching = false;
      }
    }
  }
}
