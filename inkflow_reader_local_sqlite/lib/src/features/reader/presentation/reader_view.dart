import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/library_database.dart';
import '../../../core/services/online_chapter_service.dart';
import '../../library/book.dart';
import '../domain/pagination_engine.dart';
import '../domain/reader_models.dart';
import 'reader_controller.dart';
import 'reader_settings_sheet.dart';

class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({
    required this.book,
    required this.chapters,
    this.initialChapterIndex = 0,
    super.key,
  });

  final Book book;
  final List<ChapterMarker> chapters;
  final int initialChapterIndex;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with WidgetsBindingObserver {
  final pageController = PageController(keepPage: false);
  final paginationEngine = PaginationEngine();
  final pages = <PageRange>[];
  Offset? pointerDown;
  Timer? saveTimer;
  int page = 0;
  int paginationGeneration = 0;
  int restoreOffset = 0;
  int? pendingChapterOffset;
  bool paginationComplete = false;
  bool restoredPosition = false;
  bool allowPop = false;
  String? layoutKey;
  Book? latestBook;

  // 當前章節索引
  int _currentChapterIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    WidgetsBinding.instance.addObserver(this);
  }

  /// 內建輕量網路請求
  static Future<String> _fetchHtml(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close();
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// 跨章換頁：切換至下一章
  Future<void> _goToNextChapter() async {
    if (_currentChapterIndex >= widget.chapters.length - 1) {
      debugPrint('[ReaderNav] 🛑 邊界攔截: 已達全書最後一章 (第 ${_currentChapterIndex + 1}/${widget.chapters.length} 章)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已到達全書最後一章')),
        );
      }
      return;
    }

    final nextIndex = _currentChapterIndex + 1;
    final nextChapter = widget.chapters[nextIndex];
    debugPrint('[ReaderNav] ⏩ 觸發跨章跳轉: 第 ${_currentChapterIndex + 1} 章 ➡️ 第 ${nextIndex + 1} 章 (${nextChapter.title})');

    setState(() => _currentChapterIndex = nextIndex);

    // 取得章節網址
    String targetUrl = '';
    try {
      targetUrl = ((nextChapter as dynamic).url ?? (nextChapter as dynamic).link ?? '').toString();
    } catch (_) {}

    final db = await LibraryDatabase.instance.database;
    final service = OnlineChapterService(db: db);
    final nextText = await service.getChapterText(
      bookId: widget.book.id.toString(),
      chapterIndex: nextIndex,
      chapterUrl: targetUrl,
      fetcher: _fetchHtml,
    );

    // 注入新正文與標題，原有排版引擎會自動重算分頁，版面 100% 保持原本的原汁原味
    ref.read(bookTextProvider.notifier).set(nextText);
    ref.read(bookTitleProvider.notifier).set('${widget.book.title} - ${nextChapter.title}');

    if (pageController.hasClients) {
      pageController.jumpToPage(0);
    }
  }

  /// 跨章換頁：倒退回上一章
  Future<void> _goToPrevChapter() async {
    if (_currentChapterIndex <= 0) {
      debugPrint('[ReaderNav] 🛑 邊界攔截: 已達全書第一章首頁，拒絕後退');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是全書第一章')),
        );
      }
      return;
    }

    final prevIndex = _currentChapterIndex - 1;
    final prevChapter = widget.chapters[prevIndex];
    debugPrint('[ReaderNav] ⏮️ 觸發跨章倒退: 第 ${_currentChapterIndex + 1} 章 ➡️ 第 ${prevIndex + 1} 章 (${prevChapter.title})');

    setState(() => _currentChapterIndex = prevIndex);

    String targetUrl = '';
    try {
      targetUrl = ((prevChapter as dynamic).url ?? (prevChapter as dynamic).link ?? '').toString();
    } catch (_) {}

    final db = await LibraryDatabase.instance.database;
    final service = OnlineChapterService(db: db);
    final prevText = await service.getChapterText(
      bookId: widget.book.id.toString(),
      chapterIndex: prevIndex,
      chapterUrl: targetUrl,
      fetcher: _fetchHtml,
    );

    ref.read(bookTextProvider.notifier).set(prevText);
    ref.read(bookTitleProvider.notifier).set('${widget.book.title} - ${prevChapter.title}');

    if (pageController.hasClients) {
      pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    paginationGeneration++;
    saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      saveTimer?.cancel();
      unawaited(_saveProgress());
    }
  }

  void _ensurePagination(
    String text,
    ReaderSettings settings,
    Size viewport,
    TextScaler textScaler,
  ) {
    final nextKey = [
      text.length,
      text.hashCode,
      viewport.width.toStringAsFixed(1),
      viewport.height.toStringAsFixed(1),
      textScaler.scale(1).toStringAsFixed(2),
      settings.fontFamily,
      settings.fontSize,
      settings.lineHeight,
      settings.letterSpacing,
    ].join('|');
    if (nextKey == layoutKey) return;
    if (pages.isNotEmpty) {
      restoreOffset = pages[page.clamp(0, pages.length - 1)].start;
    }
    layoutKey = nextKey;
    final generation = ++paginationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == paginationGeneration) {
        unawaited(
          _paginate(text, settings, viewport, textScaler, generation),
        );
      }
    });
  }

  Future<void> _paginate(
    String text,
    ReaderSettings settings,
    Size viewport,
    TextScaler textScaler,
    int generation,
  ) async {
    setState(() {
      pages.clear();
      page = 0;
      paginationComplete = false;
      restoredPosition = false;
    });
    var offset = 0;
    while (mounted &&
        generation == paginationGeneration &&
        offset < text.length) {
      final batch = paginationEngine.paginateBatch(
        text: text,
        startOffset: offset,
        style: settings.textStyle,
        viewport: viewport,
        textScaler: textScaler,
      );
      if (!mounted || generation != paginationGeneration) return;
      if (batch.nextOffset <= offset) {
        throw StateError('分頁排版異常');
      }
      offset = batch.nextOffset;
      setState(() {
        pages.addAll(batch.pages);
        paginationComplete = batch.isComplete;
      });
      _restoreOrJumpWhenReady();
      await Future<void>.delayed(Duration.zero);
    }
    if (mounted && generation == paginationGeneration && text.isEmpty) {
      setState(() => paginationComplete = true);
    }
  }

  void _restoreOrJumpWhenReady() {
    if (pendingChapterOffset == null && restoredPosition) return;
    final target = pendingChapterOffset ?? restoreOffset;
    if (pages.isEmpty || (!paginationComplete && pages.last.end <= target)) {
      return;
    }
    final targetPage = pages.indexWhere((range) => target < range.end);
    final index = targetPage < 0 ? pages.length - 1 : targetPage;
    pendingChapterOffset = null;
    restoredPosition = true;
    page = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pageController.hasClients) {
        pageController.jumpToPage(index);
        setState(() {});
      }
    });
  }

  /// 點擊區域判定（精準加入末頁跨章判斷）
  void _tap(double x, bool enabled) {
    if (x >= .3 && x <= .7) {
      // 點擊中間：開啟設定面板
      final currentOffset = pages.isEmpty
          ? 0
          : pages[page.clamp(0, pages.length - 1)].start;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReaderSettingsSheet(
          chapters: widget.chapters,
          currentOffset: currentOffset,
          onChapterSelected: _jumpToChapter,
        ),
      );
    } else if (enabled && x < .3) {
      // 點擊左側 30%：上翻
      if (page > 0) {
        debugPrint('[ReaderNav] 📄 前往當前章上一頁: $page/${pages.length}');
        pageController.previousPage(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      } else {
        // 第一頁向左點擊：跨章倒退
        debugPrint('[ReaderNav] ⏪ 處於章節第一頁，觸發切換上一章');
        _goToPrevChapter();
      }
    } else if (enabled && x > .7) {
      // 點擊右側 30%：下翻
      if (page < pages.length - 1) {
        debugPrint('[ReaderNav] 📄 前往當前章下一頁: ${page + 2}/${pages.length}');
        pageController.nextPage(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      } else {
        // 核心修復：最後一頁向右點擊，觸發跨章跳轉！
        debugPrint('[ReaderNav] ⏩ 已達當前章最後一頁 (${page + 1}/${pages.length})，觸發切換下一章');
        _goToNextChapter();
      }
    }
  }

  void _jumpToChapter(ChapterMarker chapter) {
    final target = pages.indexWhere((range) => chapter.offset < range.end);
    if (target >= 0 && pageController.hasClients) {
      pageController.jumpToPage(target);
      return;
    }
    pendingChapterOffset = chapter.offset;
    restoreOffset = chapter.offset;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已跳至章節位置')),
    );
  }

  void _queueProgressSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  Future<void> _saveProgress() async {
    if (pages.isEmpty) return;
    final range = pages[page.clamp(0, pages.length - 1)];
    final textLength = ref.read(bookTextProvider).length;
    if (textLength == 0) return;
    final chapter = widget.chapters.lastWhere(
      (item) => item.offset <= range.start,
      orElse: () => widget.chapters.first,
    );
    final updated = widget.book.copyWith(
      characterOffset: range.start,
      currentChapter: chapter.title,
      progressRatio: range.start / textLength,
      lastReadAt: DateTime.now(),
    );
    latestBook = updated;
    await LibraryDatabase.instance.saveProgress(updated);
  }

  Future<void> _exit() async {
    saveTimer?.cancel();
    await _saveProgress();
    if (!mounted) return;
    setState(() => allowPop = true);
    Navigator.of(context).pop(latestBook);
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(bookTextProvider);
    final title = ref.watch(bookTitleProvider);
    final settings = ref.watch(readerSettingsProvider);
    return Scaffold(
      backgroundColor: settings.backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            const padding = EdgeInsets.fromLTRB(26, 18, 26, 28);
            final viewport = Size(
              box.maxWidth - padding.horizontal,
              box.maxHeight - padding.vertical - 38,
            );
            _ensurePagination(
              text,
              settings,
              viewport,
              MediaQuery.textScalerOf(context),
            );
            final restoring =
                text.isNotEmpty && (!restoredPosition || pages.isEmpty);
            return PopScope(
              canPop: allowPop,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) unawaited(_exit());
              },
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 26, 5),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回書架',
                          onPressed: _exit,
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: settings.textColor.withValues(alpha: .65),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.3,
                              color: settings.textColor.withValues(alpha: .58),
                            ),
                          ),
                        ),
                        Text(
                          paginationComplete
                              ? (pages.isEmpty
                                  ? '0 / 0'
                                  : '${page + 1} / ${pages.length}')
                              : '${pages.isEmpty ? 0 : page + 1} 頁排版中',
                          style: TextStyle(
                            fontSize: 11,
                            color: settings.textColor.withValues(alpha: .48),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: text.isEmpty
                        ? Center(
                            child: Text(
                              '書本內容為空',
                              style: TextStyle(
                                color: settings.textColor.withValues(alpha: .6),
                              ),
                            ),
                          )
                        : restoring
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 14),
                                Text(
                                  '正在排版中...',
                                  style: TextStyle(
                                    color: settings.textColor.withValues(
                                      alpha: .65,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) =>
                                pointerDown = event.localPosition,
                            onPointerUp: (event) {
                              final start = pointerDown;
                              pointerDown = null;
                              if (start != null &&
                                  (event.localPosition - start).distance < 12) {
                                _tap(
                                  event.localPosition.dx / box.maxWidth,
                                  settings.tapPageTurnEnabled,
                                );
                              }
                            },
                            onPointerCancel: (_) => pointerDown = null,
                            child: PageView.builder(
                              controller: pageController,
                              itemCount: pages.length,
                              onPageChanged: (value) {
                                setState(() => page = value);
                                _queueProgressSave();
                              },
                              itemBuilder: (_, index) {
                                final range = pages[index];
                                return Padding(
                                  padding: padding,
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      text.substring(range.start, range.end),
                                      style: settings.textStyle,
                                      textScaler: MediaQuery.textScalerOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}