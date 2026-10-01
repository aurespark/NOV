import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'library_database.dart';

/// 閱讀模式分流列舉
enum ReadingMode {
  nativeText,      // 原生文字排版模式 (已快取或成功抽取)
  webViewFallback, // WebView 網頁保底模式 (遇反爬蟲或複雜排版)
}

/// 章節讀取結果封裝
class ChapterContentResult {
  final int chapterIndex;
  final String title;
  final String? content;       // 純文字內文 (Native 模式使用)
  final String? chapterUrl;    // 原網頁連結 (WebView 模式使用)
  final ReadingMode mode;
  final bool isFromCache;

  const ChapterContentResult({
    required this.chapterIndex,
    required this.title,
    this.content,
    this.chapterUrl,
    required this.mode,
    required this.isFromCache,
  });
}

/// 正文抽取與文字淨化器
/// 增強版正文抽取與淨化器
class ChapterContentExtractor {
  /// 主流小說網站常見的正文容器選擇器矩陣
  static const List<String> commonContentSelectors = [
    '#chaptercontent',
    '#content',
    '.read-content',
    '.novel-content',
    '#htmlContent',
    '.content',
    '.chapter-content',
    '#txtContent',
    '#BookText',
    'article',
    '.post-content',
    '.entry-content',
  ];

  /// 廣告與水印排除特徵
  static final RegExp _watermarkPattern = RegExp(
    r'(?:天才一秒記住|請記住本站網址|閱讀最新章節請到|筆趣閣|小說狂人|czbooks|無彈窗|推薦本書|上一章|下一章|章節目錄|加入書籤)',
    caseSensitive: false,
  );

  static String extractText(String html, {String? selector}) {
    if (html.trim().isEmpty) return '';

    final document = html_parser.parse(html);

    // 1. 移除腳本、樣式與不相干雜訊元素
    document
        .querySelectorAll(
          'script, style, iframe, noscript, header, footer, nav, aside, .ad, .advert, .share, .link, .recommend',
        )
        .forEach((e) => e.remove());

    dom.Element? targetElement;

    // 2. 優先使用指定的自訂選擇器
    if (selector != null && selector.isNotEmpty) {
      targetElement = document.querySelector(selector);
    }

    // 3. 遍歷常見小說正文選擇器矩陣
    if (targetElement == null) {
      for (final sel in commonContentSelectors) {
        final el = document.querySelector(sel);
        if (el != null && el.text.trim().length >= 80) {
          targetElement = el;
          break;
        }
      }
    }

    // 4. 備援啟發式：評估字元長度與段落密度加權
    if (targetElement == null) {
      int maxScore = 0;
      for (final el in document.querySelectorAll('div, article, section, main, td')) {
        final pCount = el.querySelectorAll('p').length;
        final textLength = el.text.trim().length;
        // 段落數量加權 + 內文字數
        final score = pCount * 60 + textLength;

        if (score > maxScore) {
          maxScore = score;
          targetElement = el;
        }
      }
    }

    if (targetElement == null) return '';

    // 5. 段落淨化與排版重組
    return _cleanAndFormatElement(targetElement);
  }

  static String _cleanAndFormatElement(dom.Element element) {
    // 將 <br> 替換為換行符號
    element.querySelectorAll('br').forEach((br) => br.replaceWith(dom.Text('\n')));

    final paragraphs = <String>[];
    final pTags = element.querySelectorAll('p');

    if (pTags.isNotEmpty) {
      for (final p in pTags) {
        final line = _cleanLine(p.text);
        if (line.isNotEmpty && !_watermarkPattern.hasMatch(line)) {
          paragraphs.add('  $line'); // 補齊傳統縮排
        }
      }
    } else {
      for (final rawLine in element.text.split('\n')) {
        final line = _cleanLine(rawLine);
        if (line.isNotEmpty && !_watermarkPattern.hasMatch(line)) {
          paragraphs.add('  $line');
        }
      }
    }

    return paragraphs.join('\n\n');
  }

  static String _cleanLine(String text) {
    return text
        .replaceAll(RegExp(r'[\u00a0\u3000]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// 雙模式章節排程與預載服務
class ChapterReaderService {
  final http.Client _httpClient;
  final Future<Map<String, dynamic>?> Function(String bookId, int chapterIndex)? _dbChapterGetter;
  final Future<void> Function(String bookId, int chapterIndex, String content)? _dbChapterSaver;

  ChapterReaderService({
    http.Client? httpClient,
    Future<Map<String, dynamic>?> Function(String bookId, int chapterIndex)? dbChapterGetter,
    Future<void> Function(String bookId, int chapterIndex, String content)? dbChapterSaver,
  })  : _httpClient = httpClient ?? http.Client(),
        _dbChapterGetter = dbChapterGetter,
        _dbChapterSaver = dbChapterSaver;

  static final ChapterReaderService instance = ChapterReaderService();

  Future<Map<String, dynamic>?> _getChapter(String bookId, int index) async {
    if (_dbChapterGetter != null) return _dbChapterGetter!(bookId, index);
    return await LibraryDatabase.instance.getChapter(bookId, index);
  }

  Future<void> _saveChapter(String bookId, int index, String content) async {
    if (_dbChapterSaver != null) {
      await _dbChapterSaver!(bookId, index, content);
      return;
    }
    await LibraryDatabase.instance.saveChapterContent(bookId, index, content);
  }

  /// 載入章節核心方法（雙模式調度 + 快取優先）
  Future<ChapterContentResult> loadChapter({
    required String bookId,
    required int chapterIndex,
    String? readSelector,
    bool forceRefresh = false,
  }) async {
    // 1. 檢查本地 SQLite 快取 (Cache Hit)
    final chapterData = await _getChapter(bookId, chapterIndex);
    final title = chapterData?['title'] as String? ?? '第 $chapterIndex 章';
    final url = chapterData?['chapterUrl'] as String?;

    if (!forceRefresh && chapterData != null) {
      final isSaved = (chapterData['isSaved'] as int? ?? 0) == 1;
      final cachedContent = chapterData['content'] as String?;

      if (isSaved && cachedContent != null && cachedContent.isNotEmpty) {
        return ChapterContentResult(
          chapterIndex: chapterIndex,
          title: title,
          content: cachedContent,
          chapterUrl: url,
          mode: ReadingMode.nativeText,
          isFromCache: true,
        );
      }
    }

    if (url == null || url.isEmpty) {
      return ChapterContentResult(
        chapterIndex: chapterIndex,
        title: title,
        content: null,
        chapterUrl: null,
        mode: ReadingMode.webViewFallback,
        isFromCache: false,
      );
    }

    // 2. Cache Miss：透過網路請求抓取正文
    try {
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode == 200) {
        String htmlContent;
        try {
          htmlContent = utf8.decode(response.bodyBytes);
        } catch (_) {
          htmlContent = response.body;
        }

        final cleanText = ChapterContentExtractor.extractText(htmlContent, selector: readSelector);

        if (cleanText.trim().length >= 100) {
          await _saveChapter(bookId, chapterIndex, cleanText);

          return ChapterContentResult(
            chapterIndex: chapterIndex,
            title: title,
            content: cleanText,
            chapterUrl: url,
            mode: ReadingMode.nativeText,
            isFromCache: false,
          );
        }
      }
    } catch (_) {
      // 網路或解析失敗，自動降級
    }

    // 3. 抽取失敗或反爬蟲：安全降級為 WebView 網頁閱讀模式
    return ChapterContentResult(
      chapterIndex: chapterIndex,
      title: title,
      content: null,
      chapterUrl: url,
      mode: ReadingMode.webViewFallback,
      isFromCache: false,
    );
  }

  /// 滑動即預載（背景預取後續 N 章）
  Future<void> preloadAdjacentChapters({
    required String bookId,
    required int currentChapterIndex,
    String? readSelector,
    int preloadCount = 2,
  }) async {
    for (int i = 1; i <= preloadCount; i++) {
      final targetIndex = currentChapterIndex + i;
      final cached = await _getChapter(bookId, targetIndex);

      // 若已快取則跳過
      if (cached != null && (cached['isSaved'] as int? ?? 0) == 1) {
        continue;
      }

      // 非同步觸發抓取並寫入快取
      await loadChapter(
        bookId: bookId,
        chapterIndex: targetIndex,
        readSelector: readSelector,
      );
    }
  }
}