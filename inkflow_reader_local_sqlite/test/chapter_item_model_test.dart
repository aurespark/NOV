import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';

void main() {
  group('階段一：ChapterItem 資料模型測試', () {
    test('toMap 與 fromMap 雙向序列化正確性（含 isSaved 布林值轉換）', () {
      final now = DateTime.now();
      final item = ChapterItem(
        id: 1,
        bookId: 'book_abc',
        chapterIndex: 3,
        title: '第三章 逆轉乾坤',
        characterOffset: 1024,
        chapterUrl: 'https://novel.example.com/3.html',
        isSaved: true,
        content: '這是已快取的內文。',
        cachedAt: now,
      );

      // 1. 轉為 SQLite Map 格式
      final map = item.toMap();
      expect(map['id'], 1);
      expect(map['bookId'], 'book_abc');
      expect(map['chapterIndex'], 3);
      expect(map['title'], '第三章 逆轉乾坤');
      expect(map['isSaved'], 1); // 驗證 true 被轉為 SQLite INTEGER 1
      expect(map['content'], '這是已快取的內文。');

      // 2. 從 Map 反序列化回 Dart 物件
      final restored = ChapterItem.fromMap(map);
      expect(restored.id, item.id);
      expect(restored.bookId, item.bookId);
      expect(restored.chapterIndex, item.chapterIndex);
      expect(restored.title, item.title);
      expect(restored.isSaved, isTrue);
      expect(restored.content, item.content);
    });

    test('預設值與空值容錯測試', () {
      final item = ChapterItem(
        bookId: 'book_xyz',
        chapterIndex: 0,
        title: '序章',
      );

      expect(item.characterOffset, 0);
      expect(item.isSaved, isFalse);
      expect(item.chapterUrl, isNull);
      expect(item.content, isNull);

      final map = item.toMap();
      expect(map['isSaved'], 0); // 預設為 0
    });
  });
}