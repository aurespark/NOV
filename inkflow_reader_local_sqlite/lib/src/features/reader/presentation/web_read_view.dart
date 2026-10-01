import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';
import 'reader_view.dart';

class WebReadView extends StatefulWidget {
  final dynamic book;
  final List<ChapterMarker>? chapters;
  final String? initialUrl;

  const WebReadView({
    super.key,
    required this.book,
    this.chapters,
    this.initialUrl,
  });

  @override
  State<WebReadView> createState() => _WebReadViewState();
}

class _WebReadViewState extends State<WebReadView> {
  late final WebViewController _controller;

  // 載入進度狀態
  bool _isLoading = true;
  int _loadingProgress = 0;
  String _currentUrl = '';

  // 章節目錄與定位
  List<ChapterMarker> _chapters = [];
  int? _currentChapterIndex;
  String? _currentChapterTitle;

  // 防重複抓取旗標
  String _lastExtractedUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl ?? _extractBookUrl(widget.book);
    debugPrint('[WebReadView] 🚀 啟動 WebReadView, 起始網址: $_currentUrl');

    _initWebViewController();
    _loadLocalChapters();
  }

  String _extractBookUrl(dynamic book) {
    try {
      return (book.url ?? book.sourceUrl ?? book.link ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  String _getBookId() {
    try {
      return (widget.book.id ?? widget.book.bookId ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  String _getBookTitle() {
    try {
      return (widget.book.title ?? widget.book.name ?? '線上小說').toString();
    } catch (_) {
      return '線上小說';
    }
  }

  /// 1. 初始化 WebView 控制器
  void _initWebViewController() {
    debugPrint('[WebReadView] ⚙️ 設定 WebViewController 監聽器...');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            _loadingProgress = progress;
            if (progress % 50 == 0 || progress == 100) {
              debugPrint('[WebReadView] ⏳ 載入進度: $progress%');
            }
          },
          onPageStarted: (String url) {
            debugPrint('[WebReadView] 🌐 開始載入: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (String url) async {
            debugPrint('[WebReadView] 📄 網頁載入完成: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }

            // 1. 比對當前是否為已知章節
            final matched = _matchCurrentUrlToChapter(url);

            // 2. 若是目錄頁且尚未抓取過此網址，執行爬蟲
            if (!matched && _isCatalogUrl(url) && _lastExtractedUrl != url) {
              _lastExtractedUrl = url;
              await _extractCatalogFromWeb(url);
            }
          },
          onWebResourceError: (WebResourceError error) {
            // 忽略廣告等被阻擋的資源錯誤
            if (error.errorCode != -6) {
              debugPrint('[WebReadView] ⚠️ 資源錯誤: [${error.errorCode}] ${error.description}');
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('[WebReadView] 🔗 請求導向: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      );

    if (_currentUrl.isNotEmpty) {
      _controller.loadRequest(Uri.parse(_currentUrl));
    }
  }

  bool _isCatalogUrl(String url) {
    return url.contains('/n/') ||
        url.contains('/info/') ||
        url.contains('/book/') ||
        url.contains('catalog');
  }

  /// 2. 從本地 SQLite 資料庫讀取已儲存的章節目錄
  Future<void> _loadLocalChapters() async {
    final bookId = _getBookId();
    debugPrint('[DB] 🔍 開始從本地資料庫檢查現存目錄 (bookId: $bookId)...');

    try {
      // 若外部已直接傳入章節列表，優先使用
      if (widget.chapters != null && widget.chapters!.isNotEmpty) {
        _chapters = List<ChapterMarker>.from(widget.chapters!);
      } else {
        // 從 SQLite 資料庫讀取（依你的資料表結構調整）
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/inkflow_reader.db';
        final db = await openDatabase(path);

        final List<Map<String, dynamic>> maps = await db.query(
          'chapters',
          where: 'book_id = ?',
          whereArgs: [bookId],
          orderBy: 'chapter_index ASC',
        );

        if (maps.isNotEmpty) {
          _chapters = maps.map((row) {
            return ChapterMarker(
              title: (row['title'] ?? '').toString(),
              // 若 ChapterMarker 有 url 欄位：
              // url: (row['url'] ?? '').toString(),
            );
          }).toList();
        }
      }

      if (mounted) {
        setState(() {});
        debugPrint('[WebReadView] 📚 已從本地載入 ${_chapters.length} 個已存章節');
        if (_currentUrl.isNotEmpty) {
          _matchCurrentUrlToChapter(_currentUrl);
        }
      }
    } catch (e) {
      debugPrint('[DB] ⚠️ 本地目錄讀取略過或查無快取: $e');
    }
  }

  /// 3. 執行 JavaScript 抓取 ul.chapter-list 目錄
  Future<void> _extractCatalogFromWeb(String url) async {
    debugPrint('[WebCatalogExtract] 🚀 開始抓取目錄，當前網址: $url');

    const jsCode = r'''
      (function() {
        // 尋找目標目錄容器
        const selectors = [
          'ul.chapter-list',
          'div.chapter-list',
          '.chapter-list',
          '#chapter-list',
          'ul.list-group'
        ];
        
        let container = null;
        let matchedSelector = '';
        
        for (const sel of selectors) {
          const el = document.querySelector(sel);
          if (el && el.querySelectorAll('a').length > 0) {
            container = el;
            matchedSelector = sel;
            break;
          }
        }

        if (!container) {
          // 若無容器，嘗試抓取所有可能的章節 a 標籤
          const allLinks = Array.from(document.querySelectorAll("a[href*='chapter'], a[href*='/n/']"));
          if (allLinks.length > 5) {
            container = document.body;
            matchedSelector = 'body a[href]';
          }
        }

        if (!container) {
          return JSON.stringify({ success: false, selector: 'none', count: 0, chapters: [] });
        }

        const links = container.querySelectorAll('a');
        const list = [];
        let idx = 0;

        links.forEach((a) => {
          const text = (a.innerText || a.textContent || '').trim();
          const href = a.href;
          if (text && href && !href.startsWith('javascript:')) {
            list.push({
              index: idx++,
              title: text,
              url: href
            });
          }
        });

        return JSON.stringify({
          success: true,
          selector: matchedSelector,
          count: list.length,
          chapters: list
        });
      })();
    ''';

    try {
      final rawResult = await _controller.runJavaScriptReturningResult(jsCode);
      
      String jsonStr = rawResult.toString();
      // 清除可能包在外層的引號與跳脫字元
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonDecode(jsonStr);
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final bool success = data['success'] == true;
      final String selector = data['selector'] ?? '';
      final int count = data['count'] ?? 0;
      final List rawChapters = data['chapters'] ?? [];

      if (success && count > 0) {
        debugPrint('[WebCatalogExtract] 📊 命中容器: $selector ($count 個連結), 抓取到 $count 個章節');

        // 轉換為 ChapterMarker 列表
        final List<ChapterMarker> newChapterMarkers = rawChapters.map((item) {
          return ChapterMarker(
            title: (item['title'] ?? '').toString(),
            // 若你的 ChapterMarker 包含 url 等參數，可在此賦值：
            // url: (item['url'] ?? '').toString(),
          );
        }).toList();

        // 批次寫入 SQLite
        await _saveChaptersToDatabase(rawChapters);

        if (mounted) {
          setState(() {
            _chapters = newChapterMarkers;
          });
          debugPrint('[WebReadView] 📚 已從本地載入 ${_chapters.length} 個已存章節');
          _matchCurrentUrlToChapter(_currentUrl);
        }
      } else {
        debugPrint('[WebCatalogExtract] ⚠️ 未能抓取到目錄容器或連結數為 0');
      }
    } catch (e) {
      debugPrint('[WebCatalogExtract] ❌ 目錄解析執行失敗: $e');
    }
  }

  /// 4. 批次寫入 SQLite 資料庫
  Future<void> _saveChaptersToDatabase(List rawChapters) async {
    final bookId = _getBookId();
    debugPrint('[DB] 正在批次寫入/更新線上章節目錄: 共 ${rawChapters.length} 章');

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/inkflow_reader.db';
      final db = await openDatabase(path);

      // 建立 chapters 資料表（若不存在）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chapters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT,
          chapter_index INTEGER,
          title TEXT,
          url TEXT,
          UNIQUE(book_id, chapter_index) ON CONFLICT REPLACE
        )
      ''');

      // 使用 Batch 進行高效批次寫入
      final batch = db.batch();
      for (final item in rawChapters) {
        batch.insert(
          'chapters',
          {
            'book_id': bookId,
            'chapter_index': item['index'],
            'title': item['title'],
            'url': item['url'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      debugPrint('[DB] 線上章節目錄寫入完畢！');
    } catch (e) {
      debugPrint('[DB] ⚠️ 寫入 SQLite 異常: $e');
    }
  }

  /// 5. 根據當前網址比對章節
  bool _matchCurrentUrlToChapter(String url) {
    if (_chapters.isEmpty) return false;

    for (int i = 0; i < _chapters.length; i++) {
      final dynamic ch = _chapters[i];
      String chUrl = '';
      try {
        chUrl = (ch.url ?? ch.link ?? ch.sourceUrl ?? '').toString();
      } catch (_) {}

      if (chUrl.isNotEmpty && (url == chUrl || url.contains(chUrl) || chUrl.contains(url))) {
        String title = '第 ${i + 1} 章';
        try {
          title = (ch.title ?? ch.name ?? title).toString();
        } catch (_) {}

        debugPrint('[WebReadView] 📍 目前定位於第 ${i + 1} 章: $title');

        if (mounted) {
          setState(() {
            _currentChapterIndex = i;
            _currentChapterTitle = title;
          });
        }
        return true;
      }
    }
    return false;
  }

  /// 6. 點擊進入原生閱讀器視窗
  void _navigateToReader() {
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('章節目錄載入中，請稍候...')),
      );
      return;
    }

    final targetIndex = _currentChapterIndex ?? 0;
    debugPrint('[Navigation] 🚀 使用者點擊進入原生閱讀視窗！');
    debugPrint('[Navigation] 📌 書籍: ${_getBookTitle()}');
    debugPrint('[Navigation] 📌 目錄總數: ${_chapters.length} 章');
    debugPrint('[Navigation] 📌 目標章節: 第 ${targetIndex + 1} 章');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReaderView(
          book: widget.book,
          chapters: _chapters, // 👈 傳入 List<ChapterMarker>
        ),
      ),
    ).then((_) {
      debugPrint('[Navigation] 🔙 從原生閱讀器返回 WebView 介面');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool canRead = _chapters.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_getBookTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新整理',
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 底層：網頁瀏覽器
          WebViewWidget(controller: _controller),

          // 頂部進度條
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _loadingProgress > 0 ? _loadingProgress / 100.0 : null,
              ),
            ),

          // 方案二：懸浮進入閱讀按鈕
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset: canRead ? Offset.zero : const Offset(0, 2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: canRead ? 1.0 : 0.0,
                child: canRead
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(Icons.auto_stories),
                        label: Text(
                          _currentChapterTitle != null
                              ? '進入閱讀：$_currentChapterTitle'
                              : '進入閱讀（共 ${_chapters.length} 章）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _navigateToReader,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}