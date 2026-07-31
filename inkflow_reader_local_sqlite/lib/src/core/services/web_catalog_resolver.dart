import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/reader/domain/reader_models.dart';
import 'web_url_policy.dart';

typedef WebCatalogPageLoader = Future<WebCatalogPage> Function(Uri url);
typedef LegacyCharsetDecoder =
    Future<String> Function(String charset, Uint8List bytes);

class WebCatalogPage {
  const WebCatalogPage({
    required this.url,
    required this.bytes,
    this.contentType,
  });

  final Uri url;
  final Uint8List bytes;
  final String? contentType;
}

class WebCatalogLink {
  const WebCatalogLink({
    required this.text,
    required this.href,
    required this.domPath,
    this.containerLinkCount = 1,
  });

  final String text;
  final Uri href;
  final String domPath;
  final int containerLinkCount;
}

class WebCatalogCluster {
  const WebCatalogCluster({
    required this.key,
    required this.links,
    required this.titleScore,
    required this.countScore,
    required this.varianceScore,
    required this.densityScore,
    required this.score,
    required this.selector,
  });

  final String key;
  final List<WebCatalogLink> links;
  final double titleScore;
  final double countScore;
  final double varianceScore;
  final double densityScore;
  final double score;
  final String selector;
}

enum WebCatalogCompleteness { complete, warning, fallbackRequired }

enum WebCatalogStopReason {
  exhausted,
  pageLimit,
  candidateLimit,
  noCatalog,
  staticHtmlInsufficient,
  parseFailure,
}

class WebCatalogDiagnostics {
  const WebCatalogDiagnostics({
    required this.completeness,
    required this.stopReason,
    required this.discoveredPages,
    required this.visitedPages,
    required this.chapterGroups,
    required this.chapterCount,
    required this.numberGaps,
    required this.hasUnvisitedNavigation,
    required this.hasCompletenessEvidence,
    this.latestChapterHint,
  });

  final WebCatalogCompleteness completeness;
  final WebCatalogStopReason stopReason;
  final int discoveredPages;
  final int visitedPages;
  final int chapterGroups;
  final int chapterCount;
  final List<int> numberGaps;
  final bool hasUnvisitedNavigation;
  final bool hasCompletenessEvidence;
  final int? latestChapterHint;
}

class WebCatalogResolution {
  const WebCatalogResolution({
    required this.url,
    required this.pageTitle,
    required this.links,
    required this.clusters,
    required this.bestCluster,
    required this.visitedPages,
    required this.warnings,
    required this.diagnostics,
  });

  final Uri url;
  final String? pageTitle;
  final List<WebCatalogLink> links;
  final List<WebCatalogCluster> clusters;
  final WebCatalogCluster? bestCluster;
  final List<Uri> visitedPages;
  final List<String> warnings;
  final WebCatalogDiagnostics diagnostics;

  String? get bestSelector => bestCluster?.selector;
  List<ChapterMarker> get chapterHints => [
    for (final link in bestCluster?.links ?? const <WebCatalogLink>[])
      ChapterMarker(link.text, 0),
  ];
}

class WebCatalogException implements Exception {
  const WebCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebCatalogResolver {
  WebCatalogResolver({
    WebUrlPolicy? urlPolicy,
    WebCatalogPageLoader? pageLoader,
    LegacyCharsetDecoder? legacyDecoder,
    this.maxCatalogPages = 50,
    this.maxCandidates = 100,
    this.maxDiscoveryDepth = 2,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _urlPolicy = urlPolicy ?? const WebUrlPolicy(),
       _pageLoader = pageLoader,
       _legacyDecoder =
           legacyDecoder ??
           ((charset, bytes) => CharsetConverter.decode(charset, bytes));

  final WebUrlPolicy _urlPolicy;
  final WebCatalogPageLoader? _pageLoader;
  final LegacyCharsetDecoder _legacyDecoder;
  final int maxCatalogPages;
  final int maxCandidates;
  final int maxDiscoveryDepth;
  final Duration requestTimeout;

  static final _chapterPattern = RegExp(
    r'^(第[0-9０-９一二三四五六七八九十百千零〇兩两]+[章回卷節部篇].*|(?:chapter|section)\s+[0-9０-９]+.*|序章.*|楔子.*|前言.*|後記.*|番外.*)$',
    caseSensitive: false,
  );
  static final _blockedPattern = RegExp(
    r'(captcha|驗證碼|請先登入|會員登入|付費閱讀|訂閱後閱讀|access denied|forbidden|cloudflare)',
    caseSensitive: false,
  );
  static final _errorPattern = RegExp(
    r'(404\s*not found|頁面不存在|內容不存在|系統錯誤|server error)',
    caseSensitive: false,
  );
  static final _nextCatalogPattern = RegExp(
    r'^(下一頁|下頁|更多章節|下一批|末頁|next)\s*[»›>]?$',
    caseSensitive: false,
  );
  static final _catalogEntryPattern = RegExp(
    r'(章節列表|章節目錄|全部章節|完整目錄|查看全部|目錄|開始閱讀|繼續閱讀)',
    caseSensitive: false,
  );
  static final _pageNumberPattern = RegExp(r'^[第]?\s*[0-9０-９]{1,4}\s*[頁]?$');
  static final _volumePattern = RegExp(
    r'^(正文|第?[0-9０-９一二三四五六七八九十百千零〇兩两]+卷|卷[一二三四五六七八九十0-9０-９]+).*$',
  );
  static final _looseChapterPattern = RegExp(
    r'^(?:[0-9０-９]{1,6}[\s._、：:-]+.+|正文[一二三四五六七八九十0-9０-９]+.*|序言.*|序幕.*|引子.*|尾聲.*|終章.*|大結局.*)$',
    caseSensitive: false,
  );
  static const _blacklist = <String>{
    '首頁',
    '登入',
    '註冊',
    '客服',
    '聯絡我們',
    '上一頁',
    '上一章',
    '下一章',
    '目錄',
    '章節目錄',
    '書架',
    '搜尋',
    '返回',
    '回首頁',
  };

  Future<WebCatalogResolution> resolve(Uri url) async {
    final start = _urlPolicy.normalize(url);
    final visited = <Uri>{};
    final pages = <WebCatalogResolution>[];
    final discovered = <Uri>{start};
    final queue = <({Uri url, int depth})>[(url: start, depth: 0)];
    var hitPageLimit = false;
    var hitCandidateLimit = false;
    var hadParseFailure = false;
    final explorationWarnings = <String>[];

    while (queue.isNotEmpty) {
      if (visited.length >= maxCatalogPages) {
        hitPageLimit = true;
        break;
      }
      final item = queue.removeAt(0);
      final normalized = _urlPolicy.normalize(item.url);
      if (!visited.add(normalized)) continue;
      late final WebCatalogPage page;
      late final Document document;
      late final WebCatalogResolution resolution;
      try {
        page = await (_pageLoader?.call(normalized) ?? _loadHttp(normalized));
        final decoded = await decodeHtml(page.bytes, page.contentType);
        document = html_parser.parse(decoded);
        resolution = resolveDocument(page.url, document);
      } catch (error) {
        if (error is! WebCatalogException &&
            error is! FormatException &&
            error is! http.ClientException) {
          rethrow;
        }
        if (normalized == start && pages.isEmpty) rethrow;
        hadParseFailure = true;
        explorationWarnings.add('部分目錄頁無法解析：${normalized.host}${normalized.path}');
        continue;
      }
      pages.add(resolution);

      final nextDepth = resolution.bestCluster == null
          ? item.depth + 1
          : item.depth;
      for (final candidate in _navigationUrls(
        start: start,
        base: page.url,
        document: document,
        allowCatalogDiscovery: item.depth < maxDiscoveryDepth,
      )) {
        if (discovered.length >= maxCandidates) {
          hitCandidateLimit = true;
          break;
        }
        if (nextDepth <= maxDiscoveryDepth && discovered.add(candidate)) {
          queue.add((url: candidate, depth: nextDepth));
        }
      }
    }
    if (pages.isEmpty) throw const WebCatalogException('找不到可解析的目錄頁');
    return _mergePages(
      start,
      pages,
      visited.toList(growable: false),
      discoveredPages: discovered.length,
      hasUnvisitedNavigation: queue.isNotEmpty,
      hitPageLimit: hitPageLimit,
      hitCandidateLimit: hitCandidateLimit,
      hadParseFailure: hadParseFailure,
      explorationWarnings: explorationWarnings,
    );
  }

  Future<WebCatalogPage> _loadHttp(Uri initialUrl) async {
    var current = initialUrl;
    final client = http.Client();
    try {
      for (var redirects = 0; ; redirects++) {
        _urlPolicy.validate(current, redirectCount: redirects);
        final request = http.Request('GET', current)..followRedirects = false;
        final streamed = await client.send(request).timeout(
          requestTimeout,
          onTimeout: () => throw const WebCatalogException('抓取網頁逾時'),
        );
        final response = await http.Response.fromStream(streamed);
        if (_isRedirect(response.statusCode)) {
          final location = response.headers['location'];
          if (location == null || location.trim().isEmpty) {
            throw const WebCatalogException('重新導向缺少 Location');
          }
          current = _urlPolicy.parseAndNormalize(location, baseUrl: current);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw WebCatalogException('無法抓取網頁：HTTP ${response.statusCode}');
        }
        return WebCatalogPage(
          url: current,
          bytes: Uint8List.fromList(response.bodyBytes),
          contentType: response.headers['content-type'],
        );
      }
    } finally {
      client.close();
    }
  }

  bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  Future<WebCatalogResolution> resolveHtml(
    Uri url,
    List<int> bytes, [
    String? contentType,
  ]) async {
    final html = await decodeHtml(Uint8List.fromList(bytes), contentType);
    return resolveDocument(url, html_parser.parse(html));
  }

  Future<String> decodeHtml(Uint8List bytes, String? contentType) async {
    final header = _charsetFromContentType(contentType);
    final meta = _charsetFromMeta(bytes);
    final declared = _canonicalCharset(header ?? meta);
    if (declared == 'big5' || declared == 'gbk') {
      return _legacyDecoder(declared!, bytes);
    }
    if (declared == 'utf-8') return utf8.decode(bytes, allowMalformed: true);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      for (final charset in const ['big5', 'gbk']) {
        try {
          final value = await _legacyDecoder(charset, bytes);
          if (!_looksCorrupt(value)) return value;
        } catch (_) {
          // Try the next declared fallback without using Latin-1.
        }
      }
      throw const WebCatalogException('無法判斷網頁編碼（已嘗試 UTF-8、Big5、GBK）');
    }
  }

  WebCatalogResolution resolveDocument(Uri url, Document document) {
    final bodyText = document.body?.text ?? document.documentElement?.text ?? '';
    if (_blockedPattern.hasMatch(bodyText)) {
      throw const WebCatalogException('頁面需要登入、驗證或授權，未匯入任何內容');
    }
    if (_errorPattern.hasMatch(bodyText)) {
      throw const WebCatalogException('來源回傳錯誤頁，未匯入任何內容');
    }

    final rawLinks = _collectLinks(url, document);
    final clusters = _clusterLinks(rawLinks);
    final valid = _removeSubsetClusters(
      clusters.where(_isValidCluster).toList(growable: false),
    );
    final selectedUrls = valid
        .expand((cluster) => cluster.links)
        .map((link) => _urlPolicy.normalize(link.href))
        .toSet();
    final selected = _deduplicateKeepingLast([
      for (final link in rawLinks)
        if (selectedUrls.contains(_urlPolicy.normalize(link.href))) link,
    ]);
    final best = selected.isEmpty ? null : _buildCluster('merged', selected);
    final latestChapterHint = _latestChapterHint(bodyText);
    final hasCompletenessEvidence =
        document.querySelector(
          '[id*="catalog"], [class*="catalog"], [id*="chapter"], '
          '[class*="chapter"], [id*="list"], [class*="list"]',
        ) !=
        null ||
        RegExp(r'(全部章節|完整目錄|章節列表|章節目錄)').hasMatch(bodyText);
    return WebCatalogResolution(
      url: url,
      pageTitle: _extractPageTitle(document),
      links: List.unmodifiable(selected),
      clusters: List.unmodifiable(valid),
      bestCluster: best,
      visitedPages: const [],
      warnings: best == null ? const ['未找到可信的章節目錄'] : const [],
      diagnostics: WebCatalogDiagnostics(
        completeness: best == null
            ? WebCatalogCompleteness.fallbackRequired
            : WebCatalogCompleteness.complete,
        stopReason: best == null
            ? WebCatalogStopReason.noCatalog
            : WebCatalogStopReason.exhausted,
        discoveredPages: 1,
        visitedPages: 1,
        chapterGroups: valid.length,
        chapterCount: selected.length,
        numberGaps: _chapterNumberGaps(selected),
        hasUnvisitedNavigation: false,
        hasCompletenessEvidence: hasCompletenessEvidence,
        latestChapterHint: latestChapterHint,
      ),
    );
  }

  bool _isValidCluster(WebCatalogCluster cluster) =>
      cluster.links.length >= 3 &&
      (cluster.titleScore >= 0.20 ||
          (cluster.links.length >= 5 &&
              cluster.countScore >= 0.40 &&
              cluster.densityScore >= 0.60)) &&
      cluster.score >= 0.25;

  List<WebCatalogCluster> _removeSubsetClusters(
    List<WebCatalogCluster> clusters,
  ) {
    return [
      for (final cluster in clusters)
        if (!clusters.any((other) {
          if (identical(cluster, other) ||
              other.links.length <= cluster.links.length) {
            return false;
          }
          final otherUrls = other.links
              .map((link) => _urlPolicy.normalize(link.href))
              .toSet();
          return cluster.links.every(
            (link) => otherUrls.contains(_urlPolicy.normalize(link.href)),
          );
        }))
          cluster,
    ];
  }

  WebCatalogResolution _mergePages(
    Uri start,
    List<WebCatalogResolution> pages,
    List<Uri> visited, {
    required int discoveredPages,
    required bool hasUnvisitedNavigation,
    required bool hitPageLimit,
    required bool hitCandidateLimit,
    required bool hadParseFailure,
    required List<String> explorationWarnings,
  }) {
    final selected = <WebCatalogLink>[];
    final seen = <Uri>{};
    final warnings = <String>[];
    warnings.addAll(explorationWarnings);
    for (final page in pages) {
      warnings.addAll(page.warnings);
      final pageUrls = page.clusters
          .expand((cluster) => cluster.links)
          .map((link) => _urlPolicy.normalize(link.href))
          .toSet();
      final lastIndex = <Uri, int>{};
      for (var i = 0; i < page.links.length; i++) {
        lastIndex[_urlPolicy.normalize(page.links[i].href)] = i;
      }
      for (var i = 0; i < page.links.length; i++) {
        final link = page.links[i];
        final normalized = _urlPolicy.normalize(link.href);
        if (lastIndex[normalized] == i &&
            pageUrls.contains(normalized) &&
            seen.add(normalized)) {
          selected.add(link);
        }
      }
    }
    final ordered = _correctOverallReverse(selected);
    final mergedCluster = ordered.isEmpty ? null : _buildCluster('merged', ordered);
    final gaps = _chapterNumberGaps(ordered);
    final latestChapterHint = pages
        .map((page) => page.diagnostics.latestChapterHint)
        .whereType<int>()
        .fold<int?>(null, (current, value) =>
            current == null || value > current ? value : current);
    final actualLastChapter = ordered
        .map((link) => chapterNumber(link.text))
        .whereType<int>()
        .fold<int?>(null, (current, value) =>
            current == null || value > current ? value : current);
    final latestChapterMismatch = latestChapterHint != null &&
        (actualLastChapter == null || actualLastChapter < latestChapterHint);
    final hasCompletenessEvidence = visited.length > 1 ||
        pages.any((page) => page.diagnostics.hasCompletenessEvidence);
    final groupCount = pages.fold<int>(0, (sum, page) => sum + page.clusters.length);
    final staticInsufficient =
        ordered.isEmpty ||
        gaps.length > 3 ||
        hadParseFailure ||
        latestChapterMismatch;
    final incomplete = hitPageLimit ||
        hitCandidateLimit ||
        hadParseFailure ||
        hasUnvisitedNavigation ||
        !hasCompletenessEvidence ||
        gaps.isNotEmpty;
    final stopReason = hitPageLimit
        ? WebCatalogStopReason.pageLimit
        : hitCandidateLimit
        ? WebCatalogStopReason.candidateLimit
        : hadParseFailure
        ? WebCatalogStopReason.parseFailure
        : staticInsufficient
        ? WebCatalogStopReason.staticHtmlInsufficient
        : WebCatalogStopReason.exhausted;
    if (hitPageLimit) warnings.add('已達 $maxCatalogPages 頁安全上限，目錄可能不完整');
    if (hitCandidateLimit) warnings.add('目錄候選超過 $maxCandidates 個，已停止探索');
    if (gaps.isNotEmpty && gaps.length <= 3) {
      warnings.add('章號有缺口（${gaps.join('、')}），匯入前請確認');
    }
    if (gaps.length > 3) warnings.add('章號存在多個缺口，需使用動態解析確認');
    if (hadParseFailure) warnings.add('部分目錄頁抓取失敗，需使用動態解析確認');
    if (latestChapterMismatch) {
      warnings.add('頁面顯示最新第 $latestChapterHint 章，但目前只找到第 '
          '${actualLastChapter ?? 0} 章');
    } else if (!hasCompletenessEvidence) {
      warnings.add('頁面沒有提供可驗證的完整目錄訊號，請確認章節數');
    }
    if (staticInsufficient) warnings.add('靜態 HTML 未提供足夠章節，需使用動態解析');
    if (!staticInsufficient) warnings.remove('未找到可信的章節目錄');
    return WebCatalogResolution(
      url: pages.firstWhere(
        (page) => page.bestCluster != null,
        orElse: () => pages.first,
      ).url,
      pageTitle: pages
          .map((page) => page.pageTitle)
          .whereType<String>()
          .firstOrNull,
      links: List.unmodifiable(ordered),
      clusters: mergedCluster == null ? const [] : [mergedCluster],
      bestCluster: mergedCluster,
      visitedPages: List.unmodifiable(visited),
      warnings: List.unmodifiable(warnings.toSet()),
      diagnostics: WebCatalogDiagnostics(
        completeness: staticInsufficient
            ? WebCatalogCompleteness.fallbackRequired
            : incomplete
            ? WebCatalogCompleteness.warning
            : WebCatalogCompleteness.complete,
        stopReason: stopReason,
        discoveredPages: discoveredPages,
        visitedPages: visited.length,
        chapterGroups: groupCount,
        chapterCount: ordered.length,
        numberGaps: List.unmodifiable(gaps),
        hasUnvisitedNavigation: hasUnvisitedNavigation,
        hasCompletenessEvidence: hasCompletenessEvidence,
        latestChapterHint: latestChapterHint,
      ),
    );
  }

  List<Uri> _navigationUrls({
    required Uri start,
    required Uri base,
    required Document document,
    required bool allowCatalogDiscovery,
  }) {
    final result = <Uri>[];
    final seen = <Uri>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final rel = anchor.attributes['rel']?.toLowerCase().split(RegExp(r'\s+'));
      final text = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final parentText = anchor.parent?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      final isPager = (rel?.contains('next') ?? false) ||
          _nextCatalogPattern.hasMatch(text) ||
          (_pageNumberPattern.hasMatch(text) && _looksLikePager(anchor.parent)) ||
          _looksLikePaginationHref(anchor.attributes['href'] ?? '');
      final isCatalogEntry =
          allowCatalogDiscovery && _catalogEntryPattern.hasMatch('$text $parentText');
      final isVolumeEntry =
          _volumePattern.hasMatch(text) && _looksLikeRepeatedNavigation(anchor.parent);
      if (!isPager && !isCatalogEntry && !isVolumeEntry) {
        continue;
      }
      try {
        final candidate = _urlPolicy.parseAndNormalize(
          anchor.attributes['href']!,
          baseUrl: base,
        );
        if (_sameOrigin(start, candidate) &&
            _withinBookScope(start, candidate, isCatalogEntry: isCatalogEntry) &&
            seen.add(candidate)) {
          result.add(candidate);
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  List<WebCatalogLink> _collectLinks(Uri base, Document document) {
    final result = <WebCatalogLink>[];
    for (final element in document.querySelectorAll('a[href]')) {
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || text.length > 100 || _blacklist.contains(text)) {
        continue;
      }
      final semanticChapter =
          _chapterPattern.hasMatch(text) || _looseChapterPattern.hasMatch(text);
      final structuralChapter =
          _looksLikeRepeatedNavigation(element.parent) &&
          !_catalogEntryPattern.hasMatch(text) &&
          !_pageNumberPattern.hasMatch(text);
      if (!semanticChapter && !structuralChapter) continue;
      try {
        final href = _urlPolicy.parseAndNormalize(
          element.attributes['href']!,
          baseUrl: base,
        );
        result.add(
          WebCatalogLink(
            text: text,
            href: href,
            domPath: _domPath(element),
            containerLinkCount: _candidateContainer(element)
                .querySelectorAll('a[href]')
                .length,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  List<WebCatalogLink> _deduplicateKeepingLast(List<WebCatalogLink> links) {
    final lastIndex = <Uri, int>{};
    for (var i = 0; i < links.length; i++) {
      lastIndex[_urlPolicy.normalize(links[i].href)] = i;
    }
    return [
      for (var i = 0; i < links.length; i++)
        if (lastIndex[_urlPolicy.normalize(links[i].href)] == i) links[i],
    ];
  }

  List<WebCatalogCluster> _clusterLinks(List<WebCatalogLink> links) {
    final grouped = <String, List<WebCatalogLink>>{};
    for (final link in links) {
      final key = '${_clusterDomKey(link.domPath)}|${_urlTemplate(link.href)}';
      grouped.putIfAbsent(key, () => []).add(link);
    }
    final result = [
      for (final entry in grouped.entries) _buildCluster(entry.key, entry.value),
    ]..sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.key.compareTo(b.key);
    });
    return result;
  }

  WebCatalogCluster _buildCluster(String key, List<WebCatalogLink> links) {
    final titleScore =
        links.where((link) =>
          _chapterPattern.hasMatch(link.text) ||
          _looseChapterPattern.hasMatch(link.text)).length /
        links.length;
    final countScore = (links.length / 12).clamp(0, 1).toDouble();
    final mean =
        links.map((link) => link.text.length).reduce((a, b) => a + b) /
        links.length;
    final variance =
        links
            .map((link) => (link.text.length - mean) * (link.text.length - mean))
            .reduce((a, b) => a + b) /
        links.length;
    final varianceScore = 1 / (1 + MathHelper.sqrt(variance) / mean);
    final maxContainerLinks = links
        .map((link) => link.containerLinkCount)
        .fold<int>(1, (current, value) => value > current ? value : current);
    final densityScore =
        (links.length / maxContainerLinks).clamp(0, 1).toDouble();
    final score =
        0.45 * titleScore +
        0.20 * countScore +
        0.15 * varianceScore +
        0.20 * densityScore;
    return WebCatalogCluster(
      key: key,
      links: List.unmodifiable(links),
      titleScore: titleScore,
      countScore: countScore,
      varianceScore: varianceScore,
      densityScore: densityScore,
      score: score,
      selector: key == 'merged' ? 'a' : '${key.split('|').first} a',
    );
  }

  List<WebCatalogLink> _correctOverallReverse(List<WebCatalogLink> links) {
    if (links.length < 5) return links;
    final numbered = <({int index, int number})>[];
    for (var i = 0; i < links.length; i++) {
      final number = chapterNumber(links[i].text);
      if (number != null) numbered.add((index: i, number: number));
    }
    if (numbered.length < 5) return links;
    var decreasing = 0;
    var comparisons = 0;
    for (var i = 1; i < numbered.length; i++) {
      if (numbered[i].number == numbered[i - 1].number) continue;
      comparisons++;
      if (numbered[i].number < numbered[i - 1].number) decreasing++;
    }
    if (comparisons == 0 || decreasing / comparisons < 0.70) return links;
    return links.reversed.toList(growable: false);
  }

  static int? chapterNumber(String title) {
    final match = RegExp(
      r'(?:第|chapter\s*|section\s*)?([0-9０-９一二三四五六七八九十百千零〇兩两]+)(?=\s*[章回卷節部篇._、：:\-\s]|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (match == null) return null;
    final raw = match.group(1)!;
    final ascii = raw.replaceAllMapped(
      RegExp(r'[０-９]'),
      (value) => String.fromCharCode(value.group(0)!.codeUnitAt(0) - 0xfee0),
    );
    final direct = int.tryParse(ascii);
    if (direct != null) return direct;
    return _parseChineseNumber(ascii);
  }

  static int? _parseChineseNumber(String value) {
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '兩': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = {'十': 10, '百': 100, '千': 1000};
    var total = 0;
    var digit = 0;
    var recognized = false;
    for (final char in value.split('')) {
      if (digits.containsKey(char)) {
        digit = digits[char]!;
        recognized = true;
      } else if (units.containsKey(char)) {
        total += (digit == 0 ? 1 : digit) * units[char]!;
        digit = 0;
        recognized = true;
      } else {
        return null;
      }
    }
    return recognized ? total + digit : null;
  }

  String _clusterDomKey(String path) {
    final parts = path.split(' > ');
    final ancestors = parts.take(parts.length - 1).toList();
    for (var i = ancestors.length - 1; i >= 0; i--) {
      if (ancestors[i].contains('#') || ancestors[i].contains('.')) {
        return ancestors.take(i + 1).join(' > ');
      }
    }
    return ancestors.isEmpty ? 'body' : ancestors.last;
  }

  String _urlTemplate(Uri uri) => uri.pathSegments
      .map((segment) => segment.replaceAll(RegExp(r'\d+'), '{num}'))
      .join('/');

  String _domPath(Element element) {
    final parts = <String>[];
    Node? current = element;
    while (current is Element) {
      final label = StringBuffer(current.localName ?? 'node');
      if (current.id.trim().isNotEmpty) label.write('#${current.id.trim()}');
      final classes = current.classes.where((value) => value.trim().isNotEmpty);
      if (classes.isNotEmpty) label.write('.${classes.take(2).join('.')}');
      parts.add(label.toString());
      current = current.parent;
    }
    return parts.reversed.join(' > ');
  }

  Element _candidateContainer(Element element) {
    var current = element.parent ?? element;
    while (current.parent != null &&
        current.querySelectorAll('a[href]').length < 3) {
      current = current.parent!;
    }
    return current;
  }

  String? _extractPageTitle(Document document) {
    for (final selector in [
      'meta[property="og:title"]',
      'h1',
      'title',
      'h2',
    ]) {
      final element = document.querySelector(selector);
      final value = selector.startsWith('meta')
          ? element?.attributes['content']?.trim()
          : element?.text.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _charsetFromContentType(String? value) => value == null
      ? null
      : RegExp(
          r"""charset\s*=\s*["']?([A-Za-z0-9_\-]+)""",
          caseSensitive: false,
        ).firstMatch(value)?.group(1);

  String? _charsetFromMeta(Uint8List bytes) {
    final head = latin1.decode(
      bytes.take(8192).toList(growable: false),
      allowInvalid: true,
    );
    return RegExp(
          r"""<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_\-]+)""",
          caseSensitive: false,
        ).firstMatch(head)?.group(1) ??
        RegExp(
          r"""<meta[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([A-Za-z0-9_\-]+)""",
          caseSensitive: false,
        ).firstMatch(head)?.group(1);
  }

  String? _canonicalCharset(String? value) {
    final charset = value?.toLowerCase().replaceAll('_', '-');
    if (charset == null) return null;
    if (charset == 'utf8' || charset == 'utf-8' || charset == 'us-ascii') {
      return 'utf-8';
    }
    if (charset == 'big5' ||
        charset == 'big-5' ||
        charset == 'cp950' ||
        charset == 'windows-950') {
      return 'big5';
    }
    if (charset == 'gbk' ||
        charset == 'gb2312' ||
        charset == 'gb18030' ||
        charset == 'cp936') {
      return 'gbk';
    }
    return null;
  }

  bool _looksCorrupt(String value) {
    if (value.isEmpty || value.contains('\ufffd')) return true;
    final controls = value.runes.where((rune) => rune < 32 && rune != 10).length;
    return controls > value.length ~/ 50;
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  bool _withinBookScope(Uri start, Uri candidate, {required bool isCatalogEntry}) {
    final startTokens = _bookIdentityTokens(start);
    final candidateTokens = _bookIdentityTokens(candidate);
    if (startTokens.isEmpty) {
      return isCatalogEntry || start.path == candidate.path;
    }
    return startTokens.any(candidateTokens.contains);
  }

  Set<String> _bookIdentityTokens(Uri uri) {
    const generic = {
      'book',
      'books',
      'novel',
      'novels',
      'read',
      'chapter',
      'chapters',
      'catalog',
      'catalogue',
      'list',
      'index',
      '目錄',
    };
    final queryTokens = <String>{
      for (final entry in uri.queryParameters.entries)
        if (const {'id', 'book', 'bookid', 'novel', 'novelid'}
            .contains(entry.key.toLowerCase()))
          'book=${entry.value.toLowerCase()}',
    };
    if (queryTokens.isNotEmpty) return queryTokens;
    final segments = uri.pathSegments
        .map((segment) => segment
            .toLowerCase()
            .replaceAll(RegExp(r'\.(?:html?|shtml)$'), '')
            .trim())
        .toList();
    for (var i = 0; i < segments.length - 1; i++) {
      if (const {'book', 'books', 'novel', 'novels'}.contains(segments[i]) &&
          segments[i + 1].isNotEmpty) {
        return {segments[i + 1]};
      }
    }
    return segments
        .where((segment) =>
            segment.isNotEmpty &&
            !generic.contains(segment) &&
            !_looksLikePageToken(segment))
        .take(1)
        .toSet();
  }

  bool _looksLikePageToken(String value) =>
      RegExp(r'^(?:page|p|index)[_-]?\d{1,3}$').hasMatch(value);

  bool _looksLikePager(Element? parent) {
    if (parent == null) return false;
    final label = '${parent.id} ${parent.className}'.toLowerCase();
    final numericLinks = parent
        .querySelectorAll('a[href]')
        .where((item) => _pageNumberPattern.hasMatch(item.text.trim()))
        .length;
    return numericLinks >= 2 ||
        RegExp(r'(page|pager|pagination|分頁|頁碼)').hasMatch(label);
  }

  bool _looksLikeRepeatedNavigation(Element? parent) {
    if (parent == null) return false;
    final anchors = parent.querySelectorAll('a[href]');
    if (anchors.length >= 3) return true;
    final grandParent = parent.parent;
    return grandParent != null && grandParent.querySelectorAll('a[href]').length >= 3;
  }

  bool _looksLikePaginationHref(String href) => RegExp(
    r'([?&](?:page|p)=\d+|(?:index|list|catalog)[_-]?\d+\.(?:html?|shtml)$)',
    caseSensitive: false,
  ).hasMatch(href);

  static List<int> _chapterNumberGaps(List<WebCatalogLink> links) {
    final numbers = links
        .map((link) => chapterNumber(link.text))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    if (numbers.length < 3) return const [];
    final result = <int>[];
    for (var i = 1; i < numbers.length; i++) {
      final distance = numbers[i] - numbers[i - 1];
      if (distance > 1 && distance <= 20) {
        result.addAll([
          for (var value = numbers[i - 1] + 1; value < numbers[i]; value++) value,
        ]);
      }
    }
    return result;
  }

  static int? _latestChapterHint(String text) {
    final match = RegExp(
      r'(?:最新章節?|最新更新|更新至)\s*[:：]?\s*(第[0-9０-９一二三四五六七八九十百千零〇兩两]+章)',
    ).firstMatch(text);
    return match == null ? null : chapterNumber(match.group(1)!);
  }
}

class MathHelper {
  static double sqrt(double value) {
    if (value <= 0) return 0;
    var result = value;
    for (var i = 0; i < 8; i++) {
      result = 0.5 * (result + value / result);
    }
    return result;
  }
}
