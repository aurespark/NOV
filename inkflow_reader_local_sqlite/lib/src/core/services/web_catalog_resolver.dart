import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/library/book.dart';
import '../../features/reader/domain/reader_models.dart';
import 'library_database.dart';

/// 站點特定規則配置
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

/// 解析結果封裝
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

  /// 章節正則特徵（支援中英文常見章節格式）
  static final RegExp _chapterPattern = RegExp(
    r'(?:第\s*[0-9一二三四五六七八九十百千零]+\s*[章回節卷]|Chapter\s*\d+|序章|楔子|尾聲|番外)',
    caseSensitive: false,
  );

  /// 常見雜訊排除正則
  static final RegExp _noisePattern = RegExp(
    r'^(?:首頁|主頁|書架|加入書籤|目錄|推薦|留言|登入|註冊|排行|版權|下一頁|上一頁|返回)',
    caseSensitive: false,
  );

  /// 內建常見小說站點規則庫
  final Map<String, SiteRule> _siteRules = {
    'qidian.com': const SiteRule(
      domain: 'qidian.com',
      catalogSelector: '.volume li a',
    ),
    'biquge.com': const SiteRule(
      domain: 'biquge.com',
      catalogSelector: '#list dd a',
    ),
  };

  void registerSiteRule(SiteRule rule) {
    _siteRules[rule.domain] = rule;
  }

  /// 抓取遠端網頁、解析目錄，並直接批次同步至本地 SQLite
  Future<List<ChapterItem>> fetchAndSyncCatalog(Book book) async {
    if (book.catalogUrl == null || book.catalogUrl!.trim().isEmpty) {
      throw ArgumentError('書籍目錄網址不能為空');
    }

    final normalizedUrl = _normalizeUrl(book.catalogUrl!);
    final uri = Uri.parse(normalizedUrl);

    final response = await http.get(
      uri,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('無法載入目錄網頁，HTTP 狀態碼：${response.statusCode}');
    }

    String htmlContent;
    try {
      htmlContent = utf8.decode(response.bodyBytes);
    } catch (_) {
      htmlContent = response.body;
    }

    final result = resolve(
      bookId: book.id,
      rawUrl: normalizedUrl,
      htmlContent: htmlContent,
      customSelector: null,
    );

    if (result.chapters.isEmpty) {
      throw Exception('未能從該網頁成功識別出任何章節');
    }

    final chapterMapList = result.chapters.map((c) => c.toMap()).toList();
    await LibraryDatabase.instance.insertOrUpdateCatalog(book.id, chapterMapList);

    return result.chapters;
  }

  /// 執行 DOM 目錄解析核心邏輯
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