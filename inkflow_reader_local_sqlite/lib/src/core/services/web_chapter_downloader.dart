import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/library/web_novel_models.dart';
import 'library_database.dart';
import 'web_url_policy.dart';

typedef DynamicHtmlLoader = Future<String?> Function(Uri uri);

class WebChapterDownloader {
  WebChapterDownloader({
    required this.database,
    http.Client? client,
    WebUrlPolicy? urlPolicy,
    this.dynamicHtmlLoader,
    this.maxPages = 10,
    this.minimumCharacters = 300,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _urlPolicy = urlPolicy ?? const WebUrlPolicy();

  final LibraryDatabase database;
  final http.Client _client;
  final bool _ownsClient;
  final WebUrlPolicy _urlPolicy;
  final DynamicHtmlLoader? dynamicHtmlLoader;
  final int maxPages;
  final int minimumCharacters;
  static Future<void> _downloadTail = Future<void>.value();

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<WebDownloadResult> download(WebChapter chapter) {
    final result = Completer<WebDownloadResult>();
    _downloadTail = _downloadTail.then((_) async {
      try {
        result.complete(await _downloadExclusive(chapter));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<WebDownloadResult> _downloadExclusive(WebChapter chapter) async {
    final chapterId = chapter.id;
    if (chapterId == null) throw StateError('Chapter must be persisted first');
    final persisted = await database.loadWebChapter(chapterId) ?? chapter;
    if (persisted.status == WebChapterStatus.complete &&
        (persisted.content?.trim().isNotEmpty ?? false)) {
      return WebDownloadResult(
        status: WebChapterStatus.complete,
        content: persisted.content!,
        pages: await database.loadWebChapterPages(chapterId),
      );
    }
    await database.updateWebChapterStatus(
      chapterId,
      WebChapterStatus.downloading,
      attemptedAt: DateTime.now().toUtc(),
    );
    final pages = <WebChapterPage>[];
    final visited = <Uri>{};
    var current = _urlPolicy.parseAndNormalize(persisted.url);
    WebDownloadError? error;
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      if (!visited.add(current)) break;
      try {
        final loaded = await _load(current);
        final extracted = await _extractWithDynamicFallback(
          loaded,
          chapterTitle: persisted.title,
        );
        pages.add(
          WebChapterPage(
            chapterId: chapterId,
            pageIndex: pageIndex,
            sourceUrl: loaded.finalUrl.toString(),
            normalizedUrl: _urlPolicy.normalize(loaded.finalUrl).toString(),
            content: extracted.content,
            status: WebPageStatus.complete,
            lastAttemptAt: DateTime.now().toUtc(),
          ),
        );
        final next = extracted.nextPage;
        if (next == null || visited.contains(next)) break;
        current = next;
      } on WebDownloadException catch (caught) {
        error = caught.error;
        pages.add(
          WebChapterPage(
            chapterId: chapterId,
            pageIndex: pageIndex,
            sourceUrl: current.toString(),
            normalizedUrl: _urlPolicy.normalize(current).toString(),
            status: caught.error.type == WebDownloadErrorType.blocked
                ? WebPageStatus.blocked
                : WebPageStatus.failed,
            errorReason: caught.error.message,
            retryCount: 1,
            lastAttemptAt: DateTime.now().toUtc(),
          ),
        );
        break;
      }
    }
    final readable = pages
        .where((page) => page.content?.trim().isNotEmpty ?? false)
        .toList();
    final content = mergePages(readable.map((page) => page.content!).toList());
    final status =
        error?.type == WebDownloadErrorType.blocked && readable.isEmpty
        ? WebChapterStatus.blocked
        : readable.isEmpty
        ? WebChapterStatus.failed
        : error == null
        ? WebChapterStatus.complete
        : WebChapterStatus.partial;
    final result = WebDownloadResult(
      status: status,
      content: content,
      pages: pages,
      error: error,
    );
    await database.finishWebChapterDownload(chapterId, result);
    return result;
  }

  Future<WebContentExtraction> _extractWithDynamicFallback(
    _LoadedHtml loaded, {
    required String chapterTitle,
  }) async {
    try {
      return extract(
        loaded.html,
        pageUrl: loaded.finalUrl,
        chapterTitle: chapterTitle,
      );
    } on WebDownloadException catch (error) {
      if (error.error.type != WebDownloadErrorType.parse ||
          dynamicHtmlLoader == null) {
        rethrow;
      }
      final dynamic = await dynamicHtmlLoader!(loaded.finalUrl);
      if (dynamic == null || dynamic.trim().isEmpty) rethrow;
      return extract(
        dynamic,
        pageUrl: loaded.finalUrl,
        chapterTitle: chapterTitle,
      );
    }
  }

  Future<_LoadedHtml> _load(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(
              uri,
              headers: const {
                HttpHeaders.userAgentHeader: 'Mozilla/5.0 InkflowReader/0.6',
                HttpHeaders.acceptHeader: 'text/html,application/xhtml+xml',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 429 || response.statusCode == 503) {
          final delay =
              _retryAfter(response.headers['retry-after']) ??
              Duration(seconds: attempt + 1);
          await Future<void>.delayed(delay);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw WebDownloadException(
            WebDownloadError(
              type: response.statusCode == 401 || response.statusCode == 403
                  ? WebDownloadErrorType.blocked
                  : WebDownloadErrorType.http,
              message: 'HTTP ${response.statusCode}',
              httpStatus: response.statusCode,
            ),
          );
        }
        final finalUrl = response.request?.url ?? uri;
        var html = _decode(
          response.bodyBytes,
          response.headers['content-type'],
        );
        if (_isBlocked(html)) {
          throw WebDownloadException(
            const WebDownloadError(
              type: WebDownloadErrorType.blocked,
              message: '頁面需要登入、驗證或付費權限',
            ),
          );
        }
        if (_effectiveCharacters(html_parser.parse(html).body?.text ?? '') <
            minimumCharacters) {
          final dynamic = await dynamicHtmlLoader?.call(finalUrl);
          if (dynamic != null && dynamic.trim().isNotEmpty) html = dynamic;
        }
        return _LoadedHtml(html, finalUrl);
      } on WebDownloadException {
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw WebDownloadException(
      WebDownloadError(
        type: lastError is TimeoutException
            ? WebDownloadErrorType.timeout
            : WebDownloadErrorType.network,
        message: '網路連線失敗',
      ),
    );
  }

  WebContentExtraction extract(
    String html, {
    required Uri pageUrl,
    required String chapterTitle,
  }) {
    final document = html_parser.parse(html);
    if (_isBlocked(document.body?.text ?? '')) {
      throw WebDownloadException(
        const WebDownloadError(
          type: WebDownloadErrorType.blocked,
          message: '頁面需要登入、驗證或付費權限',
        ),
      );
    }
    for (final selector in const [
      'script',
      'style',
      'nav',
      'header',
      'footer',
      'form',
      'iframe',
      'noscript',
      '.advertisement',
      '.ads',
      '.ad',
    ]) {
      document.querySelectorAll(selector).forEach((node) => node.remove());
    }
    final candidates = document.querySelectorAll(
      'article, main, [role=main], #content, #chaptercontent, .content, .chapter-content, .read-content, body',
    );
    Element? best;
    double bestScore = -1;
    for (final candidate in candidates) {
      final text = _extractReadableText(candidate);
      final links = candidate
          .querySelectorAll('a')
          .fold<int>(0, (sum, link) => sum + link.text.length);
      final score =
          text.length -
          links * 2 -
          candidate.querySelectorAll('input,button,select').length * 80;
      if (score > bestScore) {
        bestScore = score.toDouble();
        best = candidate;
      }
    }
    var content = _extractReadableText(best);
    content = _removeDuplicateTitle(content, chapterTitle);
    if (_effectiveCharacters(content) < minimumCharacters) {
      throw WebDownloadException(
        const WebDownloadError(
          type: WebDownloadErrorType.parse,
          message: '找不到足夠的正文內容',
        ),
      );
    }
    return WebContentExtraction(
      content: content,
      nextPage: _nextPage(document, pageUrl),
    );
  }

  Uri? _nextPage(Document document, Uri base) {
    final currentChapterSignals = document.querySelector('h1')?.text ?? '';
    for (final link in document.querySelectorAll('a[href]')) {
      final text = link.text.replaceAll(RegExp(r'\s+'), '').trim();
      if (!RegExp(
        r'^(下一頁|下頁|後一頁|next|\d+/\d+)$',
        caseSensitive: false,
      ).hasMatch(text)) {
        continue;
      }
      if (RegExp(
        r'下一章|下章|nextchapter',
        caseSensitive: false,
      ).hasMatch('$text ${link.attributes['class'] ?? ''}')) {
        continue;
      }
      try {
        final candidate = _urlPolicy.parseAndNormalize(
          link.attributes['href']!,
          baseUrl: base,
        );
        if (candidate.host == base.host &&
            !_looksLikeNextChapter(base, candidate, currentChapterSignals)) {
          return candidate;
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  bool _looksLikeNextChapter(Uri current, Uri next, String title) {
    final currentNumbers = RegExp(
      r'\d+',
    ).allMatches(current.path).map((m) => int.parse(m.group(0)!)).toList();
    final nextNumbers = RegExp(
      r'\d+',
    ).allMatches(next.path).map((m) => int.parse(m.group(0)!)).toList();
    if (currentNumbers.isEmpty || nextNumbers.isEmpty) {
      return false;
    }
    final delta = nextNumbers.last - currentNumbers.last;
    return delta == 1 &&
        !RegExp(
          r'\b(?:page|p)[=_-]?\d+',
          caseSensitive: false,
        ).hasMatch(next.toString());
  }

  static String mergePages(List<String> pages) {
    final merged = <String>[];
    for (final page in pages) {
      final paragraphs = page
          .split(RegExp(r'\n{2,}'))
          .where((p) => p.trim().isNotEmpty)
          .toList();
      while (merged.isNotEmpty &&
          paragraphs.isNotEmpty &&
          merged.last.trim() == paragraphs.first.trim()) {
        paragraphs.removeAt(0);
      }
      merged.addAll(paragraphs);
    }
    return merged.join('\n\n').trim();
  }

  String _decode(Uint8List bytes, String? contentType) {
    final declared = RegExp(
      r'charset\s*=\s*([^;\s]+)',
      caseSensitive: false,
    ).firstMatch(contentType ?? '')?.group(1)?.toLowerCase();
    if (declared == null || declared.contains('utf')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String _extractReadableText(Element? element) {
    if (element == null) return '';

    final html = element.innerHtml
        .replaceAll(
          RegExp(r'<br\s*/?>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'</(?:p|div|section|article|li|blockquote|h[1-6])\s*>',
            caseSensitive: false,
          ),
          '\n\n',
        );
    final fragment = html_parser.parseFragment(html);
    return _normalizeText(fragment.text);
  }

  static String _normalizeText(String input) => input
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .split(RegExp(r'\n+'))
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !RegExp(r'^(上一章|下一章|返回目錄|加入書架|手機閱讀|投推薦票)$').hasMatch(line),
      )
      .join('\n\n');

  static String _removeDuplicateTitle(String content, String title) {
    final paragraphs = content.split(RegExp(r'\n{2,}'));
    if (paragraphs.isNotEmpty && _fold(paragraphs.first) == _fold(title)) {
      paragraphs.removeAt(0);
    }
    return paragraphs.join('\n\n');
  }

  static String _fold(String value) =>
      value.replaceAll(RegExp(r'[\s：:._-]'), '').toLowerCase();
  static int _effectiveCharacters(String value) =>
      value.replaceAll(RegExp(r'\s'), '').length;
  static bool _isBlocked(String value) => RegExp(
    r'(captcha|verify you are human|請先登入|會員登入|付費章節|訂閱後閱讀|存取遭拒)',
    caseSensitive: false,
  ).hasMatch(value);
  static Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null
        ? null
        : Duration(seconds: seconds.clamp(1, 60).toInt());
  }
}

class WebContentExtraction {
  const WebContentExtraction({required this.content, this.nextPage});
  final String content;
  final Uri? nextPage;
}

class WebDownloadException implements Exception {
  const WebDownloadException(this.error);
  final WebDownloadError error;
  @override
  String toString() => error.message;
}

class _LoadedHtml {
  const _LoadedHtml(this.html, this.finalUrl);
  final String html;
  final Uri finalUrl;
}
