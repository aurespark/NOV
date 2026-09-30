import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/inkflow_scheme_router.dart';

void main() {
  group('InkflowSchemeRouter 測試組', () {
    test('能夠準確辨識內部自訂協定與一般外部 HTTP 網址', () {
      expect(InkflowSchemeRouter.isInternalScheme('inkflow://read?bookId=1'), isTrue);
      expect(InkflowSchemeRouter.isInternalScheme('inkflow://catalog?bookId=1'), isTrue);
      expect(InkflowSchemeRouter.isInternalScheme('catalog:book_100'), isTrue);
      expect(InkflowSchemeRouter.isInternalScheme('read:book_100/2'), isTrue);
      expect(InkflowSchemeRouter.isInternalScheme('https://novel.example.com/ch1.html'), isFalse);
      expect(InkflowSchemeRouter.isInternalScheme('http://www.google.com'), isFalse);
    });

    test('解析標準 inkflow://read 協定為 OpenChapterAction', () {
      const url = 'inkflow://read?bookId=book_123&chapterIndex=5&chapterUrl=https://example.com/c5.html';
      final action = InkflowSchemeRouter.parse(url);

      expect(action, isA<OpenChapterAction>());
      final chapterAction = action as OpenChapterAction;
      expect(chapterAction.bookId, 'book_123');
      expect(chapterAction.chapterIndex, 5);
      expect(chapterAction.chapterUrl, 'https://example.com/c5.html');
    });

    test('解析標準 inkflow://catalog 協定為 OpenCatalogAction', () {
      const url = 'inkflow://catalog?bookId=book_123&catalogUrl=https://example.com/catalog.html';
      final action = InkflowSchemeRouter.parse(url);

      expect(action, isA<OpenCatalogAction>());
      final catalogAction = action as OpenCatalogAction;
      expect(catalogAction.bookId, 'book_123');
      expect(catalogAction.catalogUrl, 'https://example.com/catalog.html');
    });

    test('解析 inkflow://next 與 inkflow://prev 上下章切換協定', () {
      final nextAction = InkflowSchemeRouter.parse('inkflow://next?bookId=book_123&currentChapterIndex=10');
      expect(nextAction, isA<NextChapterAction>());
      expect((nextAction as NextChapterAction).bookId, 'book_123');
      expect(nextAction.currentChapterIndex, 10);

      final prevAction = InkflowSchemeRouter.parse('inkflow://prev?bookId=book_123&currentChapterIndex=10');
      expect(prevAction, isA<PrevChapterAction>());
      expect((prevAction as PrevChapterAction).bookId, 'book_123');
      expect(prevAction.currentChapterIndex, 10);
    });

    test('向下相容 APK 的 catalog: 與 read: 簡化語法', () {
      // 測試 catalog:book_999
      final apkCatalog = InkflowSchemeRouter.parse('catalog:book_999');
      expect(apkCatalog, isA<OpenCatalogAction>());
      expect((apkCatalog as OpenCatalogAction).bookId, 'book_999');

      // 測試 read:book_999/8
      final apkRead = InkflowSchemeRouter.parse('read:book_999/8');
      expect(apkRead, isA<OpenChapterAction>());
      final readAction = apkRead as OpenChapterAction;
      expect(readAction.bookId, 'book_999');
      expect(readAction.chapterIndex, 8);
    });

    test('能夠反向建構合法的標準 URI 字串', () {
      final readUrl = InkflowSchemeRouter.buildReadUri(bookId: 'b1', chapterIndex: 2);
      expect(readUrl, 'inkflow://read?bookId=b1&chapterIndex=2');

      final catalogUrl = InkflowSchemeRouter.buildCatalogUri(bookId: 'b1', catalogUrl: 'https://ex.com');
      expect(catalogUrl, contains('inkflow://catalog'));
      expect(catalogUrl, contains('bookId=b1'));
      expect(catalogUrl, contains('catalogUrl=https%3A%2F%2Fex.com'));
    });
  });
}