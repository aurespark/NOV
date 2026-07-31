import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_diff_service.dart';
import 'package:inkflow_reader/src/core/services/web_catalog_resolver.dart';
import 'package:inkflow_reader/src/features/library/web_novel_models.dart';

void main() {
  test('classifies added updated removed and unchanged chapters', () {
    final existing = [
      WebChapter(id: 1, url: 'https://x/1', normalizedUrl: 'https://x/1', title: '第1章', position: 0),
      WebChapter(id: 2, url: 'https://x/2-old', normalizedUrl: 'https://x/2-old', title: '第2章', position: 1),
      WebChapter(id: 3, url: 'https://x/old', normalizedUrl: 'https://x/old', title: '舊番外', position: 2),
    ];
    final incoming = [
      WebCatalogLink(text: '第1章', href: Uri.parse('https://x/1'), domPath: 'body>a', containerLinkCount: 3),
      WebCatalogLink(text: '第2章 新標題', href: Uri.parse('https://x/2'), domPath: 'body>a', containerLinkCount: 3),
      WebCatalogLink(text: '第3章', href: Uri.parse('https://x/3'), domPath: 'body>a', containerLinkCount: 3),
    ];
    final diff = const WebCatalogDiffService().compare(existing, incoming);
    expect(diff.unchanged, hasLength(1));
    expect(diff.updated, hasLength(1));
    expect(diff.added, hasLength(1));
    expect(diff.sourceRemoved, hasLength(1));
  });
}
