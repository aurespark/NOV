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

  test('以前頁長度推估探測長度，分頁結果與逐頁固定 4096 探測完全相同', () {
    final text = List.generate(120, (i) => '第$i段：楚阳睁开眼睛，只觉得浑身剧痛，四肢百骸仿佛被拆散重组。').join('\n\n');
    const style = TextStyle(fontSize: 22, height: 1.9);
    const viewport = Size(390, 720);
    final engine = PaginationEngine();
    List<PageRange> run(int maxPages) {
      final out = <PageRange>[];
      var offset = 0;
      while (offset < text.length) {
        final b = engine.paginateBatch(
          text: text, startOffset: offset, style: style, viewport: viewport,
          textScaler: TextScaler.noScaling, maxPages: maxPages, timeBudget: const Duration(seconds: 5));
        out.addAll(b.pages);
        offset = b.nextOffset;
      }
      return out;
    }
    final adaptive = run(1000); // 同一批內沿用推估的探測長度
    final fixed = run(1); // 每批只排一頁 → 每頁都從 4096 開始探測
    expect(adaptive.map((p) => '${p.start}-${p.end}'), fixed.map((p) => '${p.start}-${p.end}'));
  });
}
