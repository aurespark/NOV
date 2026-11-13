import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/library/book.dart';
import '../../features/reader/domain/reader_models.dart';
import 'library_database.dart';
import 'novel_html_extractor.dart';

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

    final htmlContent =
        await decodeHtmlBytes(response.bodyBytes, response.headers['content-type']);

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
    final chapters = await _resolveAllPages(
      bookId: targetBookId,
      pageUrl: normalizedUrl,
      html: htmlContent,
      client: httpClient,
    );

    debugPrint('[WebCatalog] ✅ 解析成功！書名:《$title》, 作者: $author, 目錄共 ${chapters.length} 章');

    return (
      title: title,
      author: author,
      coverUrl: coverUrl != null ? _resolveUrl(uri, coverUrl) : null,
      chapters: chapters,
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
          chapters: dedupeKeepLast(chapters),
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
      chapters: dedupeKeepLast(heuristicChapters),
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
    int highestScore = -1 << 30;

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

      // 非章節連結（導覽、推薦）扣分，外層大容器才不會因連結較多而勝出
      score += matchedChapterCount * 5 - (links.length - matchedChapterCount) * 2;

      if (score >= highestScore && matchedChapterCount > 0) {
        highestScore = score;
        bestContainer = container;
      }
    }

    if (bestContainer == null) return [];

    final links = bestContainer.querySelectorAll('a');
    final chapters = <ChapterItem>[];
    int index = 0;

    for (final a in links) {
      final href = a.attributes['href'];
      final title = a.text.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (href == null || href.isEmpty || href.startsWith('javascript:')) continue;
      if (title.isEmpty || _noisePattern.hasMatch(title)) continue;

      final absoluteUrl = _resolveUrl(baseUri, href);

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

  static const _maxCatalogPages = 50;

  /// 參考 APK：書籍頁若有「查看完整目錄」等連結先跳過去，
  /// 再沿「下一頁」或 <select> 分頁下拉逐頁合併。單頁失敗只停止翻頁，不丟已取得章節。
  Future<List<ChapterItem>> _resolveAllPages({
    required String bookId,
    required String pageUrl,
    required String html,
    required http.Client client,
  }) async {
    final entry = findCatalogEntryUrl(html, pageUrl);
    if (entry != null) {
      try {
        debugPrint('[WebCatalog] ↪️ 進入完整目錄頁: $entry');
        html = await fetchNovelHtml(entry, client: client);
        pageUrl = entry;
      } catch (e) {
        debugPrint('[WebCatalog] ⚠️ 完整目錄頁載入失敗，沿用原頁: $e');
      }
    }

    final all = <ChapterItem>[];
    final seenPages = <String>{pageUrl};
    while (true) {
      final page = resolve(bookId: bookId, rawUrl: pageUrl, htmlContent: html).chapters;
      if (page.isEmpty && all.isNotEmpty) break; // 「下一頁」不是目錄分頁
      all.addAll(page);
      final next = findNextCatalogPageUrl(html, pageUrl);
      if (next == null || !seenPages.add(next) || seenPages.length > _maxCatalogPages) break;
      try {
        debugPrint('[WebCatalog] ➡️ 目錄下一頁: $next');
        html = await fetchNovelHtml(next, client: client);
        pageUrl = next;
      } catch (e) {
        debugPrint('[WebCatalog] ⚠️ 目錄分頁載入失敗，停止翻頁: $e');
        break;
      }
    }
    final unique = dedupeKeepLast(all);
    return [
      for (var i = 0; i < unique.length; i++)
        ChapterItem(
          bookId: bookId,
          chapterIndex: i,
          title: unique[i].title,
          chapterUrl: unique[i].chapterUrl,
        ),
    ];
  }

  static const _catalogEntryWords = [
    '章节目录', '章節目錄', '查看完整目录', '查看完整目錄', '完整目录', '完整目錄',
    '全部章节', '全部章節', '查看更多章节', '查看更多章節', '查看目录', '查看目錄',
  ];

  /// 書籍介紹頁上的「完整目錄」入口（APK 也限制文字 ≤10 字，避免誤抓長句）。
  static String? findCatalogEntryUrl(String html, String pageUrl) {
    final base = Uri.parse(pageUrl);
    for (final a in html_parser.parse(html).querySelectorAll('a[href]')) {
      final text = a.text.trim();
      if (text.length > 10 || !_catalogEntryWords.any(text.contains)) continue;
      final url = _absolute(base, a.attributes['href']!);
      if (url != null && url != pageUrl) return url;
    }
    return null;
  }

  static const _nextPageWords = ['下一页', '下一頁', '下页', '下頁', '后一页', '後一頁'];

  static String? findNextCatalogPageUrl(String html, String pageUrl) {
    final base = Uri.parse(pageUrl);
    final doc = html_parser.parse(html);
    for (final a in doc.querySelectorAll('a[href]')) {
      final text = a.text.trim();
      if (text.length > 6 || !_nextPageWords.any(text.contains)) continue;
      final url = _absolute(base, a.attributes['href']!);
      if (url != null && url != pageUrl) return url;
    }
    // 手機版常見 <select><option value="/book/1/index_2.html">第2頁</option>
    for (final select in doc.querySelectorAll('select')) {
      final options = select.querySelectorAll('option');
      final current = options.indexWhere((o) =>
          o.attributes.containsKey('selected') ||
          _absolute(base, o.attributes['value'] ?? '') == pageUrl);
      if (current < 0 || current + 1 >= options.length) continue;
      final url = _absolute(base, options[current + 1].attributes['value'] ?? '');
      if (url != null && url != pageUrl) return url;
    }
    return null;
  }

  static String? _absolute(Uri base, String href) {
    if (href.isEmpty || href.startsWith('javascript') || href.startsWith('#')) return null;
    try {
      final u = base.resolve(href);
      return u.host == base.host ? u.toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// 同網址保留「最後」一次出現：多數站點在目錄頂端放「最新章節」區塊，
  /// 保留最後一次才不會把最新幾章排到第一章前面。
  static List<ChapterItem> dedupeKeepLast(List<ChapterItem> chapters) {
    final lastIndex = <String, int>{};
    for (var i = 0; i < chapters.length; i++) {
      lastIndex[chapters[i].chapterUrl ?? ''] = i;
    }
    final out = <ChapterItem>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (lastIndex[c.chapterUrl ?? ''] != i) continue;
      out.add(ChapterItem(
        bookId: c.bookId,
        chapterIndex: out.length,
        title: c.title,
        chapterUrl: c.chapterUrl,
      ));
    }
    return out;
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