import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/library/web_novel_models.dart';

void main() {
  group('WebChapter status transitions', () {
    test('rejects a transition that is not part of the state machine', () {
      final chapter = WebChapter(
        id: 1,
        bookId: 'book-1',
        url: 'https://example.com/chapter/1',
        title: '第一章',
        position: 0,
      );

      expect(
        () => chapter.transitionTo(WebChapterStatus.complete, content: '正文'),
        throwsStateError,
      );
    });

    test('supports every transition allowed by the specification', () {
      const allowed = <WebChapterStatus, Set<WebChapterStatus>>{
        WebChapterStatus.pending: {WebChapterStatus.downloading},
        WebChapterStatus.downloading: {
          WebChapterStatus.pending,
          WebChapterStatus.complete,
          WebChapterStatus.partial,
          WebChapterStatus.failed,
          WebChapterStatus.blocked,
        },
        WebChapterStatus.complete: {WebChapterStatus.downloading},
        WebChapterStatus.partial: {WebChapterStatus.downloading},
        WebChapterStatus.failed: {WebChapterStatus.downloading},
        WebChapterStatus.blocked: {WebChapterStatus.downloading},
      };

      for (final entry in allowed.entries) {
        for (final target in WebChapterStatus.values) {
          expect(
            entry.key.canTransitionTo(target),
            entry.value.contains(target),
            reason: '${entry.key.name} -> ${target.name}',
          );
        }
      }
    });

    test('complete and partial chapters require readable content', () {
      final downloading = WebChapter(
        id: 1,
        bookId: 'book-1',
        url: 'https://example.com/chapter/1',
        title: '第一章',
        position: 0,
        status: WebChapterStatus.downloading,
      );

      expect(
        () => downloading.transitionTo(WebChapterStatus.complete),
        throwsStateError,
      );
      expect(
        () => downloading.transitionTo(WebChapterStatus.partial, content: ' '),
        throwsStateError,
      );
      expect(
        downloading
            .transitionTo(WebChapterStatus.complete, content: '有效正文')
            .isDownloaded,
        isTrue,
      );
    });

    test('rejects content changes before a usable download result', () {
      final cached = WebChapter(
        id: 1,
        bookId: 'book-1',
        url: 'https://example.com/chapter/1',
        title: '第一章',
        position: 0,
        status: WebChapterStatus.complete,
        content: '既有正文',
      );
      final pending = WebChapter(
        id: 2,
        bookId: 'book-1',
        url: 'https://example.com/chapter/2',
        title: '第二章',
        position: 1,
      );

      expect(
        () => cached.transitionTo(
          WebChapterStatus.downloading,
          content: '未驗證的新正文',
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            pending.transitionTo(WebChapterStatus.downloading, content: '錯誤頁面'),
        throwsArgumentError,
      );
    });
  });

  test('WebChapter map round-trip keeps persisted fields', () {
    final attemptedAt = DateTime.utc(2026, 7, 30, 2);
    final chapter = WebChapter(
      id: 7,
      bookId: 'book-1',
      url: 'https://example.com/chapter/7',
      normalizedUrl: 'https://example.com/chapter/7',
      title: '第七章',
      position: 6,
      content: '正文',
      status: WebChapterStatus.complete,
      retryCount: 2,
      lastError: '曾經逾時',
      lastAttemptAt: attemptedAt,
      isSourceRemoved: true,
      createdAt: attemptedAt,
      updatedAt: attemptedAt,
    );

    final restored = WebChapter.fromMap(chapter.toMap());

    expect(restored.id, 7);
    expect(restored.bookId, 'book-1');
    expect(restored.status, WebChapterStatus.complete);
    expect(restored.isDownloaded, isTrue);
    expect(restored.content, '正文');
    expect(restored.retryCount, 2);
    expect(restored.isSourceRemoved, isTrue);
  });

  test('download result enforces status and content invariants', () {
    expect(
      () => WebDownloadResult(status: WebChapterStatus.pending, content: ''),
      throwsArgumentError,
    );
    expect(
      () => WebDownloadResult(status: WebChapterStatus.complete, content: ''),
      throwsArgumentError,
    );
    expect(
      WebDownloadResult(
        status: WebChapterStatus.partial,
        content: '已取得的正文',
        pages: [
          WebChapterPage(
            chapterId: 1,
            pageIndex: 0,
            sourceUrl: 'https://example.com/1',
            content: '已取得的正文',
            status: WebPageStatus.complete,
          ),
        ],
      ).status,
      WebChapterStatus.partial,
    );
    expect(
      () => WebDownloadResult(
        status: WebChapterStatus.failed,
        content: '不得覆蓋的內容',
      ),
      throwsArgumentError,
    );
    expect(
      () => WebChapterPage(
        chapterId: 1,
        pageIndex: 0,
        sourceUrl: 'https://example.com/1',
        content: '',
        status: WebPageStatus.complete,
      ),
      throwsArgumentError,
    );
  });

  test('only complete chapters report isDownloaded', () {
    for (final status in WebChapterStatus.values) {
      final chapter = WebChapter(
        url: 'https://example.com/${status.name}',
        title: status.name,
        position: status.index,
        status: status,
        content:
            status == WebChapterStatus.partial ||
                status == WebChapterStatus.complete
            ? '正文'
            : null,
      );

      expect(
        chapter.isDownloaded,
        status == WebChapterStatus.complete,
        reason: status.name,
      );
    }
  });

  test('catalog diff exposes all four result groups', () {
    final added = WebCatalogChange(
      type: WebCatalogChangeType.added,
      incoming: WebChapter(
        url: 'https://example.com/2',
        title: '第二章',
        position: 1,
      ),
    );
    const unchanged = WebCatalogChange(
      type: WebCatalogChangeType.unchanged,
      existingChapterId: 1,
    );
    final diff = WebCatalogDiff(changes: [added, unchanged]);

    expect(diff.added, [added]);
    expect(diff.updated, isEmpty);
    expect(diff.sourceRemoved, isEmpty);
    expect(diff.unchanged, [unchanged]);
  });
}
