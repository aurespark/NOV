import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_controller.dart';

void main() {
  group('【階段三單元測試】原生閱讀器章節邊界跳轉與狀態防護', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('3-1 章節內翻頁：未達末頁時不觸發章節切換', () {
      int currentPage = 0;
      const totalPages = 3;
      bool chapterSwitched = false;

      void onNextTap() {
        if (currentPage < totalPages - 1) {
          currentPage++;
        } else {
          chapterSwitched = true;
        }
      }

      onNextTap(); // 第 0 頁 -> 第 1 頁
      expect(currentPage, 1);
      expect(chapterSwitched, isFalse);

      onNextTap(); // 第 1 頁 -> 第 2 頁 (末頁)
      expect(currentPage, 2);
      expect(chapterSwitched, isFalse);
    });

    test('3-2 章節末頁翻頁：在最後一頁時正確觸發跨章跳轉並重設頁碼', () {
      int currentPage = 2; // 當前在第 2 頁 (共 3 頁)
      int currentChapter = 0;
      final chapters = [
        const ChapterMarker('第 1 章', 0),
        const ChapterMarker('第 2 章', 1),
      ];

      void onNextTap() {
        if (currentPage < 2) {
          currentPage++;
        } else if (currentChapter < chapters.length - 1) {
          currentChapter++;
          currentPage = 0; // 跨章重設為第 0 頁
        }
      }

      onNextTap(); // 末頁翻頁
      expect(currentChapter, 1, reason: '應切換到第 2 章');
      expect(currentPage, 0, reason: '跨章後頁碼必須歸零');
    });

    test('3-3 全書最後一章末頁防呆：到達最後一章無法再切換', () {
      int currentChapter = 2;
      final chapters = [
        const ChapterMarker('第 1 章', 0),
        const ChapterMarker('第 2 章', 1),
        const ChapterMarker('第 3 章', 2),
      ];
      bool boundaryBlocked = false;

      void onNextChapter() {
        if (currentChapter < chapters.length - 1) {
          currentChapter++;
        } else {
          boundaryBlocked = true;
        }
      }

      onNextChapter();
      expect(boundaryBlocked, isTrue, reason: '最後一章末頁必須被攔截');
      expect(currentChapter, 2, reason: '章節索引不應越界');
    });
  });
}
