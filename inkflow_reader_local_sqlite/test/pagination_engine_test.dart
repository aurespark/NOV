import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/reader/domain/pagination_engine.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pagination covers text without gaps', () {
    const text = '第一段文字。\n第二段文字。\n第三段文字。';
    final engine = PaginationEngine();
    final pages = <PageRange>[];
    var offset = 0;
    while (offset < text.length) {
      final result = engine.paginateBatch(
        text: text,
        startOffset: offset,
        style: const TextStyle(fontSize: 18, height: 1.6),
        viewport: const Size(120, 60),
        textScaler: TextScaler.noScaling,
        maxPages: 100,
      );
      pages.addAll(result.pages);
      offset = result.nextOffset;
    }
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i - 1].end, pages[i].start);
    }
  });

  test('chapter parser finds Chinese and English headings', () {
    const text = '序章\n開始。\n\n第一章 相遇\n內容。\n\nChapter 2 Goodbye\n結束。';
    final chapters = ChapterParser.parse(text);
    expect(chapters.map((chapter) => chapter.title), [
      '序章',
      '第一章 相遇',
      'Chapter 2 Goodbye',
    ]);
    expect(
      chapters.map((chapter) => chapter.offset),
      orderedEquals([0, 8, 20]),
    );
  });

  test('large TXT pagination is contiguous', () {
    final text = List.filled(20000, '這是一段測試文字。').join('\n');
    final engine = PaginationEngine();
    final pages = <PageRange>[];
    var offset = 0;
    while (offset < text.length) {
      final batch = engine.paginateBatch(
        text: text,
        startOffset: offset,
        style: const TextStyle(fontSize: 21, height: 1.75),
        viewport: const Size(340, 620),
        textScaler: TextScaler.noScaling,
      );
      expect(batch.pages.length, lessThanOrEqualTo(6));
      expect(batch.nextOffset, greaterThan(offset));
      pages.addAll(batch.pages);
      offset = batch.nextOffset;
    }
    expect(pages.length, greaterThan(3));
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i - 1].end, pages[i].start);
    }
  });
}
