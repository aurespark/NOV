import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';
import 'package:inkflow_reader/src/features/library/book.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';

void main() {
  test('M0 TXT baseline preserves importable text, chapters, and progress', () {
    const text = '''
Chapter 1 Start
The first page.

Chapter 2 Rising
The second page.
''';

    final chapters = ChapterParser.parse(text);
    expect(chapters.map((chapter) => chapter.title), [
      'Chapter 1 Start',
      'Chapter 2 Rising',
    ]);

    final book = Book(
      id: 'm0-local',
      title: 'M0 Fixture',
      author: 'Test',
      sourceType: BookSourceType.local,
      localPath: '/tmp/m0.txt',
      textEncoding: TextEncoding.utf8.name,
      characterOffset: chapters.last.offset,
      currentChapter: chapters.last.title,
      progressRatio: .5,
      createdAt: DateTime.utc(2026, 7, 30),
      isFinished: false,
    );

    final restored = Book.fromMap(book.toMap());
    expect(restored.localPath, '/tmp/m0.txt');
    expect(restored.currentChapter, 'Chapter 2 Rising');
    expect(restored.progressRatio, .5);
  });

  test('M0 web fixture is stable and does not require public websites', () {
    final file = File('test/fixtures/web_catalog/simple_catalog.html');
    final html = file.readAsBytesSync();

    final resolution = WebCatalogResolver().resolveHtml(
      Uri.parse('https://example.test/catalog'),
      html,
      'text/html; charset=utf-8',
    );

    expect(utf8.decode(html), contains('Chapter 1 Start'));
    expect(resolution.pageTitle, 'Fixture Novel');
    expect(resolution.bestSelector, contains('chapter-list'));
    expect(resolution.bestSelector, endsWith(' a'));
    expect(resolution.chapterHints.map((chapter) => chapter.title), [
      'Chapter 1 Start',
      'Chapter 2 Rising',
      'Chapter 3 Return',
    ]);
  });
}
