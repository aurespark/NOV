import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/library/book.dart';
import '../../features/reader/domain/reader_models.dart';
import 'library_database.dart';

class SiteRule {
  final String domain;
  final String? catalogSelector;
  final String? readSelector;
  final RegExp? titleCleanRegex;

  const SiteRule({
    required this.domain,
    this.catalogSelector,
    this.readSelector,
    this.titleCleanRegex,
  });
}

class CatalogResolveResult {
  final List<ChapterItem> chapters;
  final String usedStrategy;
  final String? detectedCatalogSelector;

  CatalogResolveResult({
    required this.chapters,
    required this.usedStrategy,
    this.detectedCatalogSelector,
  });
}

class WebCatalogResolver {
  static final WebCatalogResolver instance = WebCatalogResolver._internal();
  WebCatalogResolver._internal();

  /// 章節正則特徵（加入「頁/页/話/话/集/部/篇/後記」等豐富特徵）
  static final RegExp _chapterPattern = RegExp(
    r'(?:第\s*[0-9一二三四五六七八九十百千零]+\s*[章回節卷頁页話话集部篇]|\b\d{1,4}[\.、\-\s]+|Chapter\s*\d+|序章|楔子|尾聲|番外|後記|后记|大結局)',
    caseSensitive: false,
  );

  static final RegExp _noisePattern = RegExp(
    r'^(?:首頁|主頁|書架|加入書籤|目錄|推薦|留言|登入|註冊|排行|版權|下一頁|上一頁|返回)',
    caseSensitive: false,
  );

  /// 內建常見小說站點規則庫（包含小說狂人 czbooks）
  final Map<String, SiteRule> _siteRules = {
    'czbooks.net': const SiteRule(
      domain: 'czbooks.net',
      catalogSelector: '.chapter-list li a, .chapter-list a',
      readSelector: '.content',
    ),
    'qidian.com': const SiteRule(
      domain: 'qidian.com',
      catalogSelector: '.volume li a',
    ),
    'biquge.com': const SiteRule(
      domain: 'biquge.com',
      catalogSelector: '#list dd a',
    ),
  };

  /// 擬真瀏覽器請求標頭（繞過常見防爬蟲檢查）
  static Map<String, String> _buildBrowserHeaders(Uri uri) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'Referer': '${uri.scheme}://${uri.host}/',
    'Sec-Ch-Ua': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"Windows"',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Upgrade-Insecure-Requests': '1',
  };

  /// 自動從網址抓取書名、作者與章節目錄（支援詳細 Log 輸出）
  Future<({String title, String author, String? coverUrl, List<ChapterItem> chapters, bool isAntiBotProtected})>
      fetchBookInfoAndCatalog({
    required String rawUrl,
    String? bookId,
    http.Client? client,
  }) async {
    final normalizedUrl = _normalizeUrl(rawUrl);
    final uri = Uri.parse(normalizedUrl);
    final httpClient = client ?? http.Client();

    debugPrint('[WebCatalog] 🌐 發送小說連線請求: $normalizedUrl');
    final stopwatch = Stopwatch()..start();

    http.Response response;
    try {
      response = await httpClient.get(
        uri,
        headers: _buildBrowserHeaders(uri),
      );
    } catch (e) {
      debugPrint('[WebCatalog] ❌ 網路連線例外: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }

    debugPrint('[WebCatalog] 📡 伺服器回應狀態碼: ${response.statusCode} (耗時: ${stopwatch.elapsedMilliseconds}ms)');

    // 遇到 Cloudflare 或 403/503 防爬蟲時
    if (response.statusCode == 403 || response.statusCode == 503) {
      debugPrint('[WebCatalog] ⚠️ 偵測到 Cloudflare 或防爬蟲保護 (HTTP ${response.statusCode})');
      // 從網址提取預設書名，啟動容錯機制
      final domain = uri.host;
      final pathSlug = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '線上小說';
      return (
        title: '[$domain] $pathSlug',
        author: '網路來源',
        coverUrl: null,
        chapters: <ChapterItem>[],
        isAntiBotProtected: true, // 標記為防爬蟲保護
      );
    }

    if (response.statusCode != 200) {
      throw Exception('無法連線至該小說網址 (HTTP ${response.statusCode})');
    }

    String htmlContent;
    try {
      htmlContent = utf8.decode(response.bodyBytes);
    } catch (_) {
      htmlContent = response.body;
    }

    final doc = html_parser.parse(htmlContent);

    // 1. 自動辨識書名
    String? title = doc.querySelector('meta[property="og:novel:book_name"]')?.attributes['content'] ??
        doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        doc.querySelector('.book-detail h1, h1')?.text.trim();

    if (title == null || title.isEmpty) {
      final rawTitle = doc.querySelector('title')?.text.trim() ?? '';
      title = rawTitle.split(RegExp(r'[_|\-–—]')).first.trim();
    }
    if (title.isEmpty) title = '線上小說';

    // 2. 自動辨識作者
    String? author = doc.querySelector('meta[property="og:novel:author"]')?.attributes['content'] ??
        doc.querySelector('meta[name="author"]')?.attributes['content'];

    if (author == null || author.isEmpty) {
      final authorMatch = RegExp(r'作\s*者[：:\s]+([^\s<，,\|\n]+)').firstMatch(htmlContent);
      if (authorMatch != null) {
        author = authorMatch.group(1)?.trim();
      }
    }
    author ??= '未知作者';

    // 3. 封面圖
    final coverUrl = doc.querySelector('meta[property="og:image"]')?.attributes['content'];

    // 4. 解析目錄章節
    final targetBookId = bookId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final resolveResult = resolve(
      bookId: targetBookId,
      rawUrl: normalizedUrl,
      htmlContent: htmlContent,
    );

    debugPrint('[WebCatalog] ✅ 解析成功！書名:《$title》, 作者: $author, 目錄共 ${resolveResult.chapters.length} 章');

    return (
      title: title,
      author: author,
      coverUrl: coverUrl != null ? _resolveUrl(uri, coverUrl) : null,
      chapters: resolveResult.chapters,
      isAntiBotProtected: false,
    );
  }

  CatalogResolveResult resolve({
    required String bookId,
    required String rawUrl,
    required String htmlContent,
    String? customSelector,
  }) {
    final normalizedUrl = _normalizeUrl(rawUrl);
    final baseUri = Uri.parse(normalizedUrl);
    final document = html_parser.parse(htmlContent);

    SiteRule? matchedRule;
    for (final entry in _siteRules.entries) {
      if (baseUri.host.contains(entry.key)) {
        matchedRule = entry.value;
        debugPrint('[WebCatalog] 命中專屬站點規則: ${entry.key}');
        break;
      }
    }

    final activeSelector = customSelector ?? matchedRule?.catalogSelector;
    if (activeSelector != null && activeSelector.isNotEmpty) {
      final chapters = _extractBySelector(
        document: document,
        bookId: bookId,
        baseUri: baseUri,
        selector: activeSelector,
        rule: matchedRule,
      );
      if (chapters.isNotEmpty) {
        return CatalogResolveResult(
          chapters: chapters,
          usedStrategy: 'rule_selector',
          detectedCatalogSelector: activeSelector,
        );
      }
    }

    final heuristicChapters = _extractByHeuristic(
      document: document,
      bookId: bookId,
      baseUri: baseUri,
    );

    return CatalogResolveResult(
      chapters: heuristicChapters,
      usedStrategy: 'heuristic',
      detectedCatalogSelector: null,
    );
  }

  List<ChapterItem> _extractBySelector({
    required dom.Document document,
    required String bookId,
    required Uri baseUri,
    required String selector,
    SiteRule? rule,
  }) {
    final elements = document.querySelectorAll(selector);
    final chapters = <ChapterItem>[];

    int index = 0;
    for (final el in elements) {
      if (el.localName != 'a') continue;
      final href = el.attributes['href'];
      final rawTitle = el.text.trim();

      if (href == null || href.isEmpty || rawTitle.isEmpty) continue;
      if (_noisePattern.hasMatch(rawTitle)) continue;

      String finalTitle = rawTitle;
      if (rule?.titleCleanRegex != null) {
        finalTitle = finalTitle.replaceAll(rule!.titleCleanRegex!, '').trim();
      }

      final absoluteUrl = _resolveUrl(baseUri, href);

      chapters.add(ChapterItem(
        bookId: bookId,
        chapterIndex: index++,
        title: finalTitle,
        chapterUrl: absoluteUrl,
        isSaved: false,
      ));
    }
    return chapters;
  }

  List<ChapterItem> _extractByHeuristic({
    required dom.Document document,
    required String bookId,
    required Uri baseUri,
  }) {
    final candidateContainers =
        document.querySelectorAll('div, ul, ol, dl, table, section');
    dom.Element? bestContainer;
    int highestScore = -1;

    for (final container in candidateContainers) {
      final links = container.querySelectorAll('a');
      if (links.length < 5) continue;

      int score = 0;
      final className = container.className.toLowerCase();
      final idName = container.id.toLowerCase();

      if (className.contains('chapter') || idName.contains('chapter')) score += 50;
      if (className.contains('catalog') || idName.contains('catalog')) score += 50;
      if (className.contains('volume') || idName.contains('volume')) score += 30;
      if (className.contains('list') || idName.contains('list')) score += 20;

      int matchedChapterCount = 0;
      for (final a in links) {
        final text = a.text.trim();
        if (_chapterPattern.hasMatch(text)) {
          matchedChapterCount++;
        }
      }

      score += matchedChapterCount * 5;
      score += links.length;

      if (score > highestScore && matchedChapterCount > 0) {
        highestScore = score;
        bestContainer = container;
      }
    }

    if (bestContainer == null) return [];

    final links = bestContainer.querySelectorAll('a');
    final chapters = <ChapterItem>[];
    final seenUrls = <String>{};
    int index = 0;

    for (final a in links) {
      final href = a.attributes['href'];
      final title = a.text.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (href == null || href.isEmpty || href.startsWith('javascript:')) continue;
      if (title.isEmpty || _noisePattern.hasMatch(title)) continue;

      final absoluteUrl = _resolveUrl(baseUri, href);
      if (seenUrls.contains(absoluteUrl)) continue;
      seenUrls.add(absoluteUrl);

      chapters.add(ChapterItem(
        bookId: bookId,
        chapterIndex: index++,
        title: title,
        chapterUrl: absoluteUrl,
        isSaved: false,
      ));
    }

    return chapters;
  }

  String _resolveUrl(Uri baseUri, String href) {
    try {
      final parsed = Uri.parse(href);
      return baseUri.resolveUri(parsed).toString();
    } catch (_) {
      return href;
    }
  }

  String _normalizeUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    return url;
  }
}