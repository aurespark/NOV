import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/reader/domain/reader_models.dart';

class WebCatalogLink {
  const WebCatalogLink({
    required this.text,
    required this.href,
    required this.domPath,
  });

  final String text;
  final Uri href;
  final String domPath;
}

class WebCatalogCluster {
  const WebCatalogCluster({
    required this.key,
    required this.links,
    required this.titleScore,
    required this.countScore,
    required this.varianceScore,
    required this.score,
    required this.selector,
  });

  final String key;
  final List<WebCatalogLink> links;
  final double titleScore;
  final double countScore;
  final double varianceScore;
  final double score;
  final String selector;
}

class WebCatalogResolution {
  const WebCatalogResolution({
    required this.url,
    required this.pageTitle,
    required this.links,
    required this.clusters,
    required this.bestCluster,
  });

  final Uri url;
  final String? pageTitle;
  final List<WebCatalogLink> links;
  final List<WebCatalogCluster> clusters;
  final WebCatalogCluster? bestCluster;

  String? get bestSelector => bestCluster?.selector;

  List<ChapterMarker> get chapterHints => bestCluster == null
      ? const [ChapterMarker('全文', 0)]
      : [
          for (final link in bestCluster!.links)
            ChapterMarker(link.text, 0),
        ];
}

class WebCatalogResolver {
  static final _chapterPattern = RegExp(
    r'^(第[0-9０-９一二三四五六七八九十百千零〇兩两]+[章回卷節部篇].*|(?:chapter|section)\s+[0-9０-９]+.*|序章|楔子|前言|後記)$',
    caseSensitive: false,
  );

  static const _blacklist = <String>{
    '首頁',
    '登入',
    '註冊',
    '客服',
    '聯絡我們',
    '上一頁',
    '下一頁',
    '上一章',
    '下一章',
    '目錄',
    '章節目錄',
    '書架',
    '搜尋',
    '返回',
    '回首頁',
  };

  static const _titleWeights = (0.55, 0.25, 0.20);

  Future<WebCatalogResolution> resolve(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('無法抓取網頁：HTTP ${response.statusCode}');
    }
    return resolveHtml(url, response.bodyBytes, response.headers['content-type']);
  }

  WebCatalogResolution resolveHtml(
    Uri url,
    List<int> bytes, [
    String? contentType,
  ]) {
    final html = _decode(bytes, contentType);
    return resolveDocument(url, html_parser.parse(html));
  }

  WebCatalogResolution resolveDocument(Uri url, Document document) {
    final links = _collectLinks(url, document);
    final clusters = _clusterLinks(links);
    final bestCluster = clusters.isEmpty
        ? null
        : clusters.reduce((a, b) => a.score >= b.score ? a : b);
    return WebCatalogResolution(
      url: url,
      pageTitle: _extractPageTitle(document),
      links: links,
      clusters: clusters,
      bestCluster: bestCluster,
    );
  }

  List<WebCatalogLink> _collectLinks(Uri baseUrl, Document document) {
    final result = <WebCatalogLink>[];
    for (final element in document.querySelectorAll('a')) {
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final hrefValue = element.attributes['href']?.trim();
      if (hrefValue == null || hrefValue.isEmpty) continue;
      if (text.isEmpty || text.length > 80) continue;
      if (_blacklist.contains(text)) continue;
      if (!_chapterPattern.hasMatch(text) && text.length < 2) continue;

      final href = _resolveHref(baseUrl, hrefValue);
      if (href == null || !(href.scheme == 'http' || href.scheme == 'https')) {
        continue;
      }
      if (href.fragment.isNotEmpty && href.path.isEmpty) continue;
      result.add(
        WebCatalogLink(
          text: text,
          href: href,
          domPath: _domPath(element),
        ),
      );
    }
    return result;
  }

  List<WebCatalogCluster> _clusterLinks(List<WebCatalogLink> links) {
    final grouped = <String, List<WebCatalogLink>>{};
    for (final link in links) {
      final urlTemplate = _urlTemplate(link.href);
      final domKey = _clusterDomKey(link.domPath);
      final key = '$domKey|$urlTemplate';
      grouped.putIfAbsent(key, () => <WebCatalogLink>[]).add(link);
    }

    final clusters = <WebCatalogCluster>[];
    for (final entry in grouped.entries) {
      final titleScore = _titleScore(entry.value);
      final countScore = _countScore(entry.value.length);
      final varianceScore = _varianceScore(entry.value.map((item) => item.text.length));
      final score =
          _titleWeights.$1 * titleScore +
          _titleWeights.$2 * countScore +
          _titleWeights.$3 * varianceScore;
      clusters.add(
        WebCatalogCluster(
          key: entry.key,
          links: List.unmodifiable(entry.value),
          titleScore: titleScore,
          countScore: countScore,
          varianceScore: varianceScore,
          score: score,
          selector: _selectorFromCluster(entry.key),
        ),
      );
    }
    clusters.sort((a, b) => b.score.compareTo(a.score));
    return clusters;
  }

  double _titleScore(List<WebCatalogLink> links) {
    if (links.isEmpty) return 0;
    final matches = links.where((link) => _chapterPattern.hasMatch(link.text)).length;
    return matches / links.length;
  }

  double _countScore(int count) {
    if (count <= 0) return 0;
    final ratio = count / 12;
    return ratio > 1 ? 1 : ratio;
  }

  double _varianceScore(Iterable<int> lengths) {
    final values = lengths.toList();
    if (values.length <= 1) return 1;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((value) => (value - mean) * (value - mean))
            .reduce((a, b) => a + b) /
        values.length;
    final standardDeviation = variance.sqrt();
    return 1 / (1 + (standardDeviation / (mean <= 0 ? 1 : mean)));
  }

  String _selectorFromCluster(String clusterKey) {
    final domPart = clusterKey.split('|').first;
    if (domPart.isEmpty) return 'a';
    final segments = domPart.split(' > ');
    final container = segments.isNotEmpty ? segments.last : domPart;
    if (container.contains('#')) {
      return '$container a';
    }
    if (container.contains('.')) {
      return '$container a';
    }
    return '$container a';
  }

  String _clusterDomKey(String domPath) {
    final parts = domPath.split(' > ');
    if (parts.isEmpty) return domPath;
    final ancestors = parts.take(parts.length - 1).toList();
    if (ancestors.isEmpty) return domPath;

    for (var i = ancestors.length - 1; i >= 0; i--) {
      final label = ancestors[i];
      if (label.contains('#') || label.contains('.')) {
        return ancestors.take(i + 1).join(' > ');
      }
    }

    final containerTags = {'ul', 'ol', 'table', 'nav', 'section', 'div', 'article', 'main'};
    for (var i = ancestors.length - 1; i >= 0; i--) {
      final tag = ancestors[i].split('#').first.split('.').first;
      if (containerTags.contains(tag)) {
        return ancestors.take(i + 1).join(' > ');
      }
    }

    return ancestors.last;
  }

  String _urlTemplate(Uri href) {
    final path = href.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.replaceAll(RegExp(r'\d+'), '{num}'))
        .join('/');
    final query = href.queryParametersAll.isEmpty
        ? ''
        : '?${href.queryParametersAll.entries.map((entry) => '${entry.key}=${entry.value.map((value) => value.replaceAll(RegExp(r'\d+'), '{num}')).join(',')}').join('&')}';
    return '/$path$query';
  }

  Uri? _resolveHref(Uri baseUrl, String href) {
    final parsed = Uri.tryParse(href);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    return baseUrl.resolveUri(parsed);
  }

  String _domPath(Element element) {
    final parts = <String>[];
    Node? current = element;
    while (current is Element) {
      parts.add(_nodeLabel(current));
      current = current.parent;
    }
    return parts.reversed.join(' > ');
  }

  String _nodeLabel(Element element) {
    final buffer = StringBuffer(element.localName ?? 'node');
    final id = element.id.trim();
    if (id.isNotEmpty) buffer.write('#$id');
    final classes = element.classes.where((value) => value.trim().isNotEmpty).toList();
    if (classes.isNotEmpty) {
      buffer.write('.${classes.take(2).join('.')}');
    }
    return buffer.toString();
  }

  String? _extractPageTitle(Document document) {
    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;
    for (final selector in ['h1', 'h2', 'meta[property="og:title"]']) {
      final element = document.querySelector(selector);
      if (element == null) continue;
      final value = selector.startsWith('meta')
          ? element.attributes['content']?.trim()
          : element.text.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _decode(List<int> bytes, String? contentType) {
    final charset = _charsetFromContentType(contentType);
    if (charset == 'utf-8' || charset == 'us-ascii' || charset == null) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return latin1.decode(bytes, allowInvalid: true);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String? _charsetFromContentType(String? contentType) {
    if (contentType == null) return null;
    final match = RegExp(r'charset=([A-Za-z0-9_\-]+)', caseSensitive: false)
        .firstMatch(contentType);
    return match?.group(1)?.toLowerCase();
  }
}

extension on double {
  double sqrt() => MathHelper.sqrt(this);
}

class MathHelper {
  static double sqrt(double value) {
    if (value <= 0) return 0;
    var x = value;
    for (var i = 0; i < 8; i++) {
      x = 0.5 * (x + value / x);
    }
    return x;
  }
}