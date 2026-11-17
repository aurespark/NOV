import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/library_database.dart';
import '../../../core/services/novel_html_extractor.dart';
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
  int pageAtDown = 0;
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
    if (_isWebBook && _currentChapterIndex + 1 < widget.chapters.length) {
      unawaited(_chapterText(_currentChapterIndex + 1)); // 預載下一章
    }
  }

  // GBK/Big5 站點需依 charset 解碼，改用共用下載器
  static Future<String> _fetchHtml(String url) => fetchNovelHtml(url);

  bool get _isWebBook => widget.book.sourceType == BookSourceType.web;

  // 載入中的章節（含背景預載），同一章只抓一次
  final _inflight = <int, Future<String>>{};
  bool _loadingChapter = false;

  Future<String> _chapterText(int index) {
    return _inflight[index] ??= () async {
      try {
        final db = await LibraryDatabase.instance.database;
        // 章節網址由 OnlineChapterService 從目錄（chapters.chapterUrl）讀取
        return await OnlineChapterService(db: db).getChapterText(
          bookId: widget.book.id.toString(),
          chapterIndex: index,
          chapterUrl: '',
          fetcher: _fetchHtml,
        );
      } finally {
        _inflight.remove(index);
      }
    }();
  }

  /// 跨章切換：上一章/下一章/目錄點選共用。toEnd 為 true 時停在該章最後一頁（往回翻時）。
  Future<void> _loadChapter(int index, {bool toEnd = false}) async {
    if (index < 0 || index >= widget.chapters.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(index < 0 ? '已是全書第一章' : '已到達全書最後一章')),
        );
      }
      return;
    }
    if (_loadingChapter) return; // 連點時忽略，避免同時載入多章
    final chapter = widget.chapters[index];
    debugPrint('[ReaderNav] 切換章節: 第 ${_currentChapterIndex + 1} 章 ➡️ 第 ${index + 1} 章 (${chapter.title})');
    setState(() => _loadingChapter = true);
    try {
      final text = await _chapterText(index);
      if (!mounted) return;
      _currentChapterIndex = index;
      // 新章從頭（或往回翻時從尾）開始，不沿用上一章的字元位置
      pendingChapterOffset = toEnd ? (text.length - 1).clamp(0, text.length) : 0;
      ref.read(bookTextProvider.notifier).set(text);
      ref.read(bookTitleProvider.notifier).set('${widget.book.title} - ${chapter.title}');
      _queueProgressSave();
      // 背景預載下一章，翻到章末時多半已在快取
      if (index + 1 < widget.chapters.length) unawaited(_chapterText(index + 1));
    } finally {
      if (mounted) setState(() => _loadingChapter = false);
    }
  }

  void _goToNextChapter() => _loadChapter(_currentChapterIndex + 1);

  void _goToPrevChapter() => _loadChapter(_currentChapterIndex - 1, toEnd: true);

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
          duration: const Duration(milliseconds: 180),
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
          duration: const Duration(milliseconds: 180),
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
    // 網路書一次只載一章，所有標記的 offset 都是 0：改為載入選中的章節
    if (_isWebBook) {
      final index = widget.chapters.indexOf(chapter);
      if (index >= 0 && index != _currentChapterIndex) unawaited(_loadChapter(index));
      return;
    }
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
    // 網路書一次只載入一章：章節以索引計，進度 = (已讀章數 + 章內比例) / 總章數
    final isWeb = widget.book.sourceType == BookSourceType.web && widget.chapters.isNotEmpty;
    final chapterIndex = _currentChapterIndex.clamp(0, widget.chapters.isEmpty ? 0 : widget.chapters.length - 1);
    final chapter = isWeb
        ? widget.chapters[chapterIndex]
        : widget.chapters.lastWhere(
            (item) => item.offset <= range.start,
            orElse: () => widget.chapters.first,
          );
    final inChapter = range.start / textLength;
    final updated = widget.book.copyWith(
      characterOffset: range.start,
      currentChapter: chapter.title,
      progressRatio: isWeb ? (chapterIndex + inChapter) / widget.chapters.length : inChapter,
      lastReadAt: DateTime.now(),
    );
    latestBook = updated;
    await LibraryDatabase.instance.saveProgress(updated);
    if (isWeb) await LibraryDatabase.instance.saveChapterIndex(widget.book.id, chapterIndex);
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
                  // 章節下載中的提示，避免換章時看起來「沒反應」
                  SizedBox(
                    height: 2,
                    child: _loadingChapter
                        ? LinearProgressIndicator(
                            minHeight: 2,
                            color: settings.textColor.withValues(alpha: .4),
                            backgroundColor: Colors.transparent,
                          )
                        : null,
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
                            onPointerDown: (event) {
                              pointerDown = event.localPosition;
                              pageAtDown = page;
                            },
                            onPointerUp: (event) {
                              final start = pointerDown;
                              pointerDown = null;
                              if (start == null || _loadingChapter) return;
                              final delta = event.localPosition - start;
                              if (delta.distance < 12) {
                                _tap(
                                  event.localPosition.dx / box.maxWidth,
                                  settings.tapPageTurnEnabled,
                                );
                              } else if (delta.dx.abs() > 60 &&
                                  delta.dx.abs() > delta.dy.abs() * 1.5) {
                                // PageView 在章首/章末滑不動，滑動手勢在此接手換章；
                                // 用按下時的頁碼判斷，避免「滑到最後一頁」的同一下就換章
                                if (delta.dx < 0 && pageAtDown >= pages.length - 1) _goToNextChapter();
                                if (delta.dx > 0 && pageAtDown == 0) _goToPrevChapter();
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