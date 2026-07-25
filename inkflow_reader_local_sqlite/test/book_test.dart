import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/library/book.dart';

void main() {
  test('Book keeps its values when copied with reading progress', () {
    final createdAt = DateTime.utc(2026, 7, 23, 12);
    final lastReadAt = DateTime.utc(2026, 7, 23, 13);
    final original = Book(
      id: 'book-1',
      title: '午後的海岸線',
      author: '林庭均',
      sourceType: BookSourceType.local,
      localPath: '/books/book-1.txt',
      coverPath: '/covers/book-1.jpg',
      characterOffset: 12580,
      currentChapter: '第十二章',
      progressRatio: .427,
      lastReadAt: lastReadAt,
      createdAt: createdAt,
      isFinished: false,
    );

    final restored = original.copyWith(
      characterOffset: 13000,
      progressRatio: .45,
    );

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.sourceType, BookSourceType.local);
    expect(restored.characterOffset, 13000);
    expect(restored.currentChapter, '第十二章');
    expect(restored.progressRatio, .45);
    expect(restored.lastReadAt, lastReadAt);
    expect(restored.createdAt, createdAt);
    expect(restored.isFinished, isFalse);
  });

  test('Book map output clamps invalid progress to the valid range', () {
    final book = Book(
      id: 'book-2',
      title: '完成的書',
      author: '未知作者',
      sourceType: BookSourceType.web,
      catalogUrl: 'https://example.com/catalog',
      characterOffset: 99,
      currentChapter: '',
      progressRatio: 1.4,
      createdAt: DateTime.utc(2026),
      isFinished: true,
    );

    expect(book.toMap()['progressRatio'], 1.0);
  });
}
