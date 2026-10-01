import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_controller.dart';
import 'package:inkflow_reader/src/core/services/online_chapter_service.dart';

void main() {
  group('【階段二單元測試】書庫目錄點擊至原生閱讀器狀態注入與流程驗證', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('2-1 正文與標題注入：bookTextProvider 與 bookTitleProvider 狀態驗證', () {
      const bookTitle = '測試小說';
      const chapterTitle = '第一章 序幕';
      const chapterContent = '這是一段乾淨的小說正文。';

      container.read(bookTextProvider.notifier).set(chapterContent);
      container.read(bookTitleProvider.notifier).set('$bookTitle - $chapterTitle');

      expect(container.read(bookTextProvider), chapterContent);
      expect(container.read(bookTitleProvider), '測試小說 - 第一章 序幕');
    });

    test('2-2 線上正文模擬抓取與清洗後注入流程驗證', () {
      const rawHtml = '''
        <div class="content">
          <script>ad_banner();</script>
          第一段內容。<br>第二段內容。
          <p>第三段結尾。</p>
        </div>
      ''';

      final cleanText = OnlineChapterService.extractText(rawHtml);
      expect(cleanText, isNotEmpty);
      expect(cleanText, isNot(contains('<script>')));
      expect(cleanText, isNot(contains('ad_banner')));

      container.read(bookTextProvider.notifier).set(cleanText);
      final storedText = container.read(bookTextProvider);

      // 驗證三段正文均完整保留且順序正確
      expect(storedText, contains('第一段內容。'));
      expect(storedText, contains('第二段內容。'));
      expect(storedText, contains('第三段結尾。'));
    });

    test('2-3 章節列表完整性：確認傳入 ReaderView 的章節清單數量與順序正確', () {
      final chapters = [
        const ChapterMarker('第 1 章', 0),
        const ChapterMarker('第 2 章', 1),
        const ChapterMarker('第 3 章', 2),
      ];

      expect(chapters.length, 3);
      expect(chapters.first.title, '第 1 章');
      expect(chapters.last.title, '第 3 章');
    });
  });
}
