import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/services/inkflow_scheme_router.dart';
import '../../../core/services/library_database.dart';
import '../../library/book.dart';
import '../domain/reader_models.dart';
import 'reader_view.dart';

class WebReadView extends ConsumerStatefulWidget {
  final Book book;
  final String initialUrl;

  const WebReadView({
    required this.book,
    required this.initialUrl,
    super.key,
  });

  @override
  ConsumerState<WebReadView> createState() => _WebReadViewState();
}

class _WebReadViewState extends ConsumerState<WebReadView> {
  late final WebViewController _controller;
  var _progress = 0.0;
  String _pageTitle = '';
  bool _canExtractText = false;
  String? _extractedContent;
  String? _extractedChapterTitle;

  // 章節導航狀態
  List<Map<String, dynamic>> _savedChapters = [];
  int _currentChapterIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.book.title;
    _loadChaptersFromDb();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100.0),
          onPageFinished: (url) async {
            setState(() => _progress = 1.0);
            debugPrint('[WebReadView] 📄 網頁載入完成: $url');
            _detectContentAndTitle();
            _matchCurrentChapter(url);
          },
          onNavigationRequest: (request) {
            if (InkflowSchemeRouter.isInternalScheme(request.url)) {
              final action = InkflowSchemeRouter.parse(request.url);
              debugPrint('[WebReadView] ⚡ 攔截內部自訂協定: $action');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  /// 從資料庫讀取已儲存的所有章節資料
  Future<void> _loadChaptersFromDb() async {
    final db = await LibraryDatabase.instance.database;
    final list = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [widget.book.id],
      orderBy: 'chapterIndex ASC',
    );
    if (mounted) {
      setState(() {
        _savedChapters = list;
      });
      debugPrint('[WebReadView] 📚 已從本地載入 ${_savedChapters.length} 個已存章節');
    }
  }

  /// 根據當前 WebView 網址比對出是第幾章
  void _matchCurrentChapter(String url) {
    if (_savedChapters.isEmpty) return;
    for (var i = 0; i < _savedChapters.length; i++) {
      final chUrl = _savedChapters[i]['chapterUrl'] as String?;
      if (chUrl != null && url.contains(chUrl.split('?').first)) {
        setState(() => _currentChapterIndex = i);
        debugPrint('[WebReadView] 📍 目前定位於第 $i 章: ${_savedChapters[i]['title']}');
        break;
      }
    }
  }

  /// 偵測頁面正文
  Future<void> _detectContentAndTitle() async {
    try {
      final realTitle = await _controller.getTitle();
      if (realTitle != null && realTitle.isNotEmpty) {
        _syncRealTitle(realTitle);
      }

      const jsDetect = '''
        (function() {
          const selectors = [
            '#chaptercontent', '#content', '.read-content',
            '.novel-content', '#htmlContent', '.content',
            'article', '.post-content'
          ];
          let bodyText = '';
          for (const s of selectors) {
            const el = document.querySelector(s);
            if (el && el.innerText.trim().length >= 100) {
              bodyText = el.innerText.trim();
              break;
            }
          }
          let heading = document.querySelector('h1, h2, .title, .chapter-title')?.innerText || '';
          return JSON.stringify({ hasContent: bodyText.length >= 100, text: bodyText, title: heading });
        })();
      ''';

      final res = await _controller.runJavaScriptReturningResult(jsDetect);
      final json = _safeJsonDecode(res.toString());
      if (json is Map && json['hasContent'] == true) {
        final text = json['text'] as String?;
        debugPrint('[WebReadView] ✨ 偵測到章節正文！標題: "${json['title']}", 字數: ${text?.length}');
        setState(() {
          _canExtractText = true;
          _extractedContent = text;
          _extractedChapterTitle = json['title'] as String?;
        });
      } else {
        setState(() => _canExtractText = false);
      }
    } catch (_) {}
  }

  void _syncRealTitle(String title) {
    if (widget.book.title.startsWith('[') || widget.book.title == '線上小說') {
      final cleanTitle = title.split(RegExp(r'[_|\-–—]')).first.trim();
      if (cleanTitle.isNotEmpty && cleanTitle != widget.book.title) {
        setState(() => _pageTitle = cleanTitle);
        final updated = widget.book.copyWith(title: cleanTitle);
        LibraryDatabase.instance.updateBook(updated);
      }
    }
  }

  /// 一鍵抓取目前 WebView 頁面的章節目錄
  Future<void> _extractCatalogFromCurrentPage() async {
    final currentUrl = await _controller.currentUrl();
    debugPrint('[WebCatalogExtract] 🚀 開始抓取目錄，當前網址: $currentUrl');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在鎖定目錄容器並提取章節...')),
    );

    const jsExtractCatalog = '''
      (function() {
        const containerSelectors = [
          'ul.chapter-list', '.chapter-list', '#chapter-list',
          '.dir-list', '#list-chapterAll', '#list', '.volume', '#chapters'
        ];

        let targetLinks = [];
        let matchedContainer = '全網頁 a 標籤';

        for (const sel of containerSelectors) {
          const el = document.querySelector(sel);
          if (el) {
            const links = Array.from(el.querySelectorAll('a'));
            if (links.length >= 5) {
              targetLinks = links;
              matchedContainer = sel + ' (' + links.length + ' 個連結)';
              break;
            }
          }
        }

        if (targetLinks.length === 0) {
          targetLinks = Array.from(document.querySelectorAll('a'));
        }

        const chapterRegex = /(?:第\\s*[0-9一二三四五六七八九十百千零]+\\s*[章回節卷頁页話话集部篇]|\\b\\d{1,4}[\\.\\、\\-\\s]+|Chapter\\s*\\d+|序章|楔子|尾聲|番外|後記|后记|大結局)/i;
        const noiseRegex = /^(首頁|主頁|書架|登入|註冊|排行|版權|下一頁|上一頁|返回|最新章節|目錄|加入書籤|推薦|回報)/;

        const chapters = [];
        const seen = new Set();

        for (let i = 0; i < targetLinks.length; i++) {
          const a = targetLinks[i];
          const text = (a.innerText || a.textContent || '').trim();
          const href = a.href;

          if (!href || text.length < 1 || noiseRegex.test(text)) continue;

          const inContainer = matchedContainer.includes('(');
          const isMatchRegex = chapterRegex.test(text);

          if ((inContainer || isMatchRegex) && !seen.has(href)) {
            seen.add(href);
            chapters.push({ title: text, url: href });
          }
        }

        return JSON.stringify({
          container: matchedContainer,
          totalPageLinks: document.querySelectorAll('a').length,
          matchedCount: chapters.length,
          chapters: chapters
        });
      })();
    ''';

    try {
      final rawResult = await _controller.runJavaScriptReturningResult(jsExtractCatalog);
      final dynamic decoded = _safeJsonDecode(rawResult.toString());

      if (decoded is! Map) {
        throw FormatException('解析失敗: $rawResult');
      }

      final list = (decoded['chapters'] as List?) ?? [];
      final container = decoded['container'] ?? '';
      debugPrint('[WebCatalogExtract] 📊 命中容器: $container, 抓取到 ${list.length} 個章節');

      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未在目前畫面找到章節。請點進小說的「目錄」分頁後再試！')),
        );
        return;
      }

      final chapterMaps = <Map<String, dynamic>>[];
      final markers = <ChapterMarker>[];

      for (var i = 0; i < list.length; i++) {
        final item = list[i] as Map;
        final title = item['title'] as String;
        final url = item['url'] as String;

        chapterMaps.add({
          'bookId': widget.book.id,
          'chapterIndex': i,
          'title': title,
          'characterOffset': 0,
          'chapterUrl': url,
          'isSaved': 0,
        });
        markers.add(ChapterMarker(title, 0));
      }

      await LibraryDatabase.instance.insertOrUpdateCatalog(widget.book.id, chapterMaps);
      await LibraryDatabase.instance.replaceChapters(widget.book.id, markers);
      await _loadChaptersFromDb();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 成功提取並儲存 ${list.length} 個章節目錄！'),
          backgroundColor: const Color(0xff536c63),
        ),
      );
    } catch (e) {
      debugPrint('[WebCatalogExtract] ❌ 抓取失敗: $e');
    }
  }

  /// 跳轉至指定序號的章節
  void _goToChapter(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _savedChapters.length) return;
    final item = _savedChapters[targetIndex];
    final url = item['chapterUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      debugPrint('[WebReadView] ⚡ 跳轉至第 $targetIndex 章: ${item['title']} ($url)');
      setState(() => _currentChapterIndex = targetIndex);
      _controller.loadRequest(Uri.parse(url));
    }
  }

  /// 彈出目錄列表抽屜
  Future<void> _showCatalogSheet() async {
    if (_savedChapters.isEmpty) {
      await _loadChaptersFromDb();
    }

    if (_savedChapters.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未儲存目錄，請先點擊右上角「抓取目錄」按鈕！')),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '章節目錄 (共 ${_savedChapters.length} 章)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '目前：第 ${_currentChapterIndex + 1} 章',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _savedChapters.length,
                itemBuilder: (context, index) {
                  final ch = _savedChapters[index];
                  final isCurrent = index == _currentChapterIndex;
                  return ListTile(
                    dense: true,
                    selected: isCurrent,
                    selectedTileColor: const Color(0xffeadfd3),
                    title: Text(ch['title'] as String? ?? '第 $index 章'),
                    trailing: isCurrent ? const Icon(Icons.check, color: Color(0xff755842)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _goToChapter(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 彈出沉浸式純文字排版閱讀畫面（支援切換章節！）
  void _openNativeReaderModal() {
    if (_extractedContent == null || _extractedContent!.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xfffbf7ef),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Scaffold(
          backgroundColor: const Color(0xfffbf7ef),
          appBar: AppBar(
            backgroundColor: const Color(0xfffbf7ef),
            elevation: 0,
            title: Text(
              _extractedChapterTitle ?? '第 ${_currentChapterIndex + 1} 章',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                tooltip: '返回網頁模式',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: SingleChildScrollView(
              child: Text(
                _extractedContent!,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.8,
                  color: Color(0xff2d251e),
                  fontFamily: 'serif',
                ),
              ),
            ),
          ),
          bottomNavigationBar: BottomAppBar(
            color: const Color(0xfff2ebd9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  onPressed: _currentChapterIndex > 0
                      ? () {
                          Navigator.pop(ctx);
                          _goToChapter(_currentChapterIndex - 1);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  label: const Text('上一章'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCatalogSheet();
                  },
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text('目錄 (${_savedChapters.length})'),
                ),
                TextButton.icon(
                  onPressed: _currentChapterIndex < _savedChapters.length - 1
                      ? () {
                          Navigator.pop(ctx);
                          _goToChapter(_currentChapterIndex + 1);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  label: const Text('下一章'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  dynamic _safeJsonDecode(String raw) {
    var text = raw.trim();
    var decoded = jsonDecode(text);
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = _currentChapterIndex > 0 && _savedChapters.isNotEmpty;
    final hasNext = _currentChapterIndex < _savedChapters.length - 1 && _savedChapters.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitle,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '查看目錄',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: _showCatalogSheet,
          ),
          IconButton(
            tooltip: '抓取目前頁面目錄',
            icon: const Icon(Icons.playlist_add_check_rounded),
            onPressed: _extractCatalogFromCurrentPage,
          ),
          IconButton(
            tooltip: '重新整理',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
          ),
        ],
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_canExtractText)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: _openNativeReaderModal,
                backgroundColor: const Color(0xff755842),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.chrome_reader_mode_rounded),
                label: const Text('轉純文字閱讀'),
              ),
            ),
        ],
      ),
      // 底部章節導航控制列
      bottomNavigationBar: _savedChapters.isNotEmpty
          ? BottomAppBar(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: hasPrev ? () => _goToChapter(_currentChapterIndex - 1) : null,
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                      label: const Text('上一章'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showCatalogSheet,
                    icon: const Icon(Icons.list_alt_rounded),
                    label: Text('第 ${_currentChapterIndex + 1} / ${_savedChapters.length} 頁'),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: hasNext ? () => _goToChapter(_currentChapterIndex + 1) : null,
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      label: const Text('下一章'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
