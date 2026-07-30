import 'package:flutter/material.dart';
import 'reader_models.dart';

class PaginationBatch {
  const PaginationBatch(this.pages, this.nextOffset, this.isComplete);
  final List<PageRange> pages;
  final int nextOffset;
  final bool isComplete;
}

/// TextPainter must stay on the UI isolate, so callers yield between batches.
class PaginationEngine {
  PaginationBatch paginateBatch({
    required String text,
    required int startOffset,
    required TextStyle style,
    required Size viewport,
    required TextScaler textScaler,
    int maxPages = 6,
    Duration timeBudget = const Duration(milliseconds: 10),
  }) {
    if (text.isEmpty || viewport.isEmpty || startOffset >= text.length) {
      return PaginationBatch(const [], text.length, true);
    }
    final stopwatch = Stopwatch()..start();
    final pages = <PageRange>[];
    var offset = startOffset.clamp(0, text.length);
    while (offset < text.length &&
        pages.length < maxPages &&
        (pages.isEmpty || stopwatch.elapsed < timeBudget)) {
      final end = _findPageEnd(text, offset, style, viewport, textScaler);
      pages.add(PageRange(offset, end));
      offset = end;
    }
    return PaginationBatch(pages, offset, offset >= text.length);
  }

  int _findPageEnd(
    String text,
    int start,
    TextStyle style,
    Size viewport,
    TextScaler textScaler,
  ) {
    // ponytail: 4096 is only the first probe; it expands when one page needs
    // more text, so correctness does not depend on a fixed characters-per-page.
    var probeLength = 4096;
    while (true) {
      final probeEnd = (start + probeLength).clamp(0, text.length);
      final probe = text.substring(start, probeEnd);
      final painter = TextPainter(
        text: TextSpan(text: probe, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: viewport.width);
      final lines = painter.computeLineMetrics();
      var height = 0.0;
      for (final line in lines) {
        if (height > 0 && height + line.height > viewport.height) {
          final y = line.baseline - line.ascent + .01;
          final position = painter.getPositionForOffset(Offset(0, y));
          final localEnd = painter.getLineBoundary(position).start;
          if (localEnd > 0) return start + localEnd;
          return (start + painter.getLineBoundary(position).end).clamp(
            start + 1,
            text.length,
          );
        }
        height += line.height;
      }
      if (probeEnd >= text.length) return text.length;
      probeLength *= 2;
    }
  }
}
