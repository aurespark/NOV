import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../features/reader/domain/reader_models.dart';
import 'content_sanitizer.dart';
import 'encoding_service.dart';

/// 正文擷取：參考 APK (cn.uujian.i.d) 的作法——先用指定 selector，
/// 否則挑「直接文字最多、連結文字最少」的容器，再把 br/p 轉成段落。
class ChapterContentExtractor {
  static const _junk =
      'script, style, noscript, iframe, ins, nav, header, footer, form, '
      'button, select, .ad, .ads, .adsbygoogle, .advertisement, .recommend, '
      '[style*="display:none"], [style*="display: none"], '
      // 小說正文幾乎不用這些標籤；hetushu 等站拿來塞「和_图_书」與網址浮水印。
      // shortcut: s/u 偶有正當的刪除線/底線用途，遇到站點真的用來排版再改成只刪含浮水印者
      'cite, var, tt, code, samp, kbd, dfn, s, u';
  static const _inline = {'p', 'span', 'font', 'strong', 'b', 'i', 'em'};
  static const _block = {
    'p', 'div', 'br', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'article',
    'section', 'tr', 'dd', 'pre',
  };

  static String extractText(String html, {String? selector}) {
    if (html.trim().isEmpty) return '';
    final doc = html_parser.parse(html);
    for (final e in doc.querySelectorAll(_junk)) {
      e.remove();
    }
    final el = _pick(doc, selector);
    if (el == null) return '';
    // 正文內的連結清單（上一章/目錄/推薦）不是正文
    for (final list in el.querySelectorAll('ul, ol, dl, table')) {
      if (_linkTextLen(list) * 2 > list.text.trim().length) list.remove();
    }
    final buf = StringBuffer();
    // 正文直接放在 <body> 下（jieqi 舊站如 piaotia）：只取 body 自身的文字，
    // 不取導覽列、工具列、頁尾聲明等子區塊
    if (el.localName == 'body' && _directTextLen(el) > 0) {
      for (final node in el.nodes) {
        if (node is dom.Text) {
          buf.write(node.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
        } else if (node is dom.Element && node.localName == 'br') {
          buf.write('\n');
        } else if (node is dom.Element && _inline.contains(node.localName)) {
          _walk(node, buf);
        }
      }
    } else {
      _walk(el, buf);
    }
    return buf
        .toString()
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'^[\s　 ]+|[\s　 ]+$'), ''))
        .where((l) => l.isNotEmpty && !ContentSanitizer.isAdLine(l))
        .join('\n\n');
  }

  static dom.Element? _pick(dom.Document doc, String? selector) {
    if (selector != null && selector.isNotEmpty) {
      try {
        final el = doc.querySelector(selector);
        if (el != null && el.text.trim().isNotEmpty) return el;
      } catch (_) {
        // 使用者自訂 selector 語法錯誤 → 改走啟發式
      }
    }
    dom.Element? best;
    var bestScore = 0;
    for (final e in doc.querySelectorAll('body, div, article, section, td, dd, pre')) {
      final s = _directTextLen(e);
      if (s > bestScore) {
        bestScore = s;
        best = e;
      }
    }
    if (best != null) return best;
    final body = doc.body;
    return (body != null && body.text.trim().isNotEmpty) ? body : null;
  }

  /// 只算容器自己的文字節點、行內子元素，以及「一段一個 div」的純文字子 div，
  /// 避免外層包裝容器分數虛高，又能認出每段落各包一層 div 的站點。
  static int _directTextLen(dom.Element e) {
    var n = 0;
    for (final node in e.nodes) {
      if (node is dom.Text) {
        n += node.text.trim().length;
      } else if (node is dom.Element &&
          (_inline.contains(node.localName) ||
              // 段落 div 只有一段：含 <br> 的是正文容器本身，不能算成父層的段落
              // body 的輸出只取自身文字，評分也不算子 div，否則會與真正的正文容器同分搶走
              (e.localName != 'body' &&
                  node.localName == 'div' &&
                  node.querySelector('div, p, br, ul, ol, dl, table') == null))) {
        n += node.text.trim().length - _linkTextLen(node);
      }
    }
    return n;
  }

  static int _linkTextLen(dom.Element e) =>
      e.querySelectorAll('a').fold(0, (n, a) => n + a.text.trim().length);

  static void _walk(dom.Node node, StringBuffer buf) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        buf.write(child.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
      } else if (child is dom.Element) {
        final block = _block.contains(child.localName);
        if (block) buf.write('\n');
        _walk(child, buf);
        if (block) buf.write('\n');
      }
    }
  }

  static const _nextPageWords = ['下一页', '下一頁', '下页', '下頁', '第二页', '第二頁', '下一小节', '下一小節'];

  /// 同章分頁（例：123.html → 123_2.html）。只接受檔名以目前頁檔名開頭的連結，
  /// 避免把「下一章」誤當成同章下一頁。
  static String? findNextPageUrl(String html, String currentUrl) {
    final base = Uri.parse(currentUrl);
    final stem = _stem(base);
    if (stem.isEmpty) return null;
    for (final a in html_parser.parse(html).querySelectorAll('a[href]')) {
      final text = a.text.trim();
      if (text.length > 8 || !_nextPageWords.any(text.contains)) continue;
      final Uri next;
      try {
        next = base.resolve(a.attributes['href']!);
      } catch (_) {
        continue;
      }
      if (next.host != base.host || next.toString() == currentUrl) continue;
      if (_stem(next) == stem && _rawStem(next) != _rawStem(base)) return next.toString();
    }
    return null;
  }

  // 「123_2」視為「123」，讓第 2 頁也能找到第 3 頁
  static String _stem(Uri u) => _rawStem(u).replaceFirst(RegExp(r'_\d+$'), '');

  static String _rawStem(Uri u) {
    final seg = u.pathSegments.where((s) => s.isNotEmpty);
    return seg.isEmpty ? '' : seg.last.split('.').first;
  }
}

/// 從 Content-Type 標頭或 <meta> 偵測編碼（APK 同樣以
/// `charset=` 正則 + `meta[charset]` 判斷，並支援 GBK）。
String? detectHtmlCharset(Uint8List bytes, String? contentType) {
  final re = RegExp(r'''charset\s*=\s*["']?([\w-]+)''', caseSensitive: false);
  final fromHeader = contentType == null ? null : re.firstMatch(contentType)?.group(1);
  if (fromHeader != null) return fromHeader.toLowerCase();
  final head = latin1.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes);
  return re.firstMatch(head)?.group(1)?.toLowerCase();
}

Future<String> decodeHtmlBytes(Uint8List bytes, String? contentType) async {
  final cs = detectHtmlCharset(bytes, contentType);
  // shortcut: gb2312/gb18030 用 gbk 解碼，罕用字可能錯；遇到再換 gb18030 解碼器
  if (cs != null && cs.startsWith('gb')) {
    return (await EncodingService().decode(bytes, TextEncoding.gbk)).text;
  }
  if (cs == 'big5') {
    return (await EncodingService().decode(bytes, TextEncoding.big5)).text;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 共用的章節/目錄 HTML 下載：瀏覽器 UA、同站 Referer、逾時、自動編碼。
Future<String> fetchNovelHtml(String url, {http.Client? client}) async {
  final uri = Uri.parse(url);
  final c = client ?? http.Client();
  try {
    final res = await c.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      'Referer': '${uri.scheme}://${uri.host}/',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', uri);
    }
    return decodeHtmlBytes(res.bodyBytes, res.headers['content-type']);
  } finally {
    if (client == null) c.close();
  }
}
