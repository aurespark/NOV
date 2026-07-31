import '../../features/library/web_novel_models.dart';
import 'web_catalog_resolver.dart';

class WebCatalogDiffService {
  const WebCatalogDiffService();

  WebCatalogDiff compare(List<WebChapter> existing, List<WebCatalogLink> incoming) {
    final unmatched = existing.toSet();
    final changes = <WebCatalogChange>[];
    for (var index = 0; index < incoming.length; index++) {
      final link = incoming[index];
      final candidate = _bestMatch(link, index, unmatched);
      final next = WebChapter(
        id: candidate?.chapter.id,
        bookId: candidate?.chapter.bookId,
        url: link.href.toString(),
        normalizedUrl: link.href.toString(),
        title: link.text,
        position: index,
        content: candidate?.chapter.content,
        status: candidate?.chapter.status ?? WebChapterStatus.pending,
        isSourceRemoved: false,
      );
      if (candidate == null) {
        changes.add(WebCatalogChange(type: WebCatalogChangeType.added, incoming: next, confidence: 1));
        continue;
      }
      unmatched.remove(candidate.chapter);
      final changed = candidate.chapter.url != next.url ||
          candidate.chapter.title != next.title ||
          candidate.chapter.position != next.position ||
          candidate.chapter.isSourceRemoved;
      changes.add(WebCatalogChange(
        type: changed ? WebCatalogChangeType.updated : WebCatalogChangeType.unchanged,
        existingChapterId: candidate.chapter.id,
        incoming: next,
        confidence: candidate.score,
      ));
    }
    for (final chapter in unmatched) {
      changes.add(WebCatalogChange(
        type: WebCatalogChangeType.sourceRemoved,
        existingChapterId: chapter.id,
        confidence: 1,
      ));
    }
    return WebCatalogDiff(changes: changes);
  }

  _Match? _bestMatch(WebCatalogLink incoming, int position, Set<WebChapter> candidates) {
    _Match? best;
    for (final chapter in candidates) {
      var score = 0.0;
      if ((chapter.normalizedUrl ?? chapter.url) == incoming.href.toString()) {
        score = 1;
      } else {
        final oldNumber = WebCatalogResolver.chapterNumber(chapter.title);
        final newNumber = WebCatalogResolver.chapterNumber(incoming.text);
        if (oldNumber != null && oldNumber == newNumber) score = .9;
        if (_normalizeTitle(chapter.title) == _normalizeTitle(incoming.text)) score = score < .82 ? .82 : score;
        if ((chapter.position - position).abs() <= 1) score += .08;
      }
      if (score >= .8 && (best == null || score > best.score)) best = _Match(chapter, score.clamp(0, 1));
    }
    return best;
  }

  String _normalizeTitle(String title) => title.replaceAll(RegExp(r'[\s：:._-]'), '').toLowerCase();
}

class _Match {
  const _Match(this.chapter, this.score);
  final WebChapter chapter;
  final double score;
}
