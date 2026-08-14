import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/library_database.dart';
import '../../core/services/safe_webview_loader.dart';
import '../../core/services/web_chapter_downloader.dart';
import '../reader/domain/pagination_engine.dart';
import '../reader/domain/reader_models.dart';
import '../reader/presentation/reader_controller.dart';
import '../reader/presentation/reader_settings_sheet.dart';
import 'book.dart';
import 'web_novel_models.dart';

class WebChapterReaderView extends ConsumerStatefulWidget {
  const WebChapterReaderView({
    super.key,
    required this.book,
    required this.chapters,
    required this.initialChapterId,
  });

  final Book book;
  final List<WebChapter> chapters;
  final int initialChapterId;

  @override
  ConsumerState<WebChapterReaderView> createState() =>
      _WebChapterReaderViewState();
}

class _WebChapterReaderViewState extends ConsumerState<WebChapterReaderView>
    with WidgetsBindingObserver {
  final _pageController = PageController(keepPage: false);
  final _paginationEngine = PaginationEngine();
  final _pageRanges = <PageRange>[];
  Timer? _saveTimer;
  Offset? _pointerDown;
  late int _index = widget.chapters
      .indexWhere((chapter) => chapter.id == widget.initialChapterId)
      .clamp(0, widget.chapters.length - 1)
      .toInt();
  late WebChapter _chapter = widget.chapters[_index];
  bool _loading = false;
  bool _showPageMarkers = false;
  List<WebChapterPage> _sourcePages = const [];
  int _page = 0;
  int _paginationGeneration = 0;
  bool _paginationComplete = false;
  bool _restoredPosition = false;
  double _restoreRatio = 0;
  String? _restoreAnchor;
  String? _layoutKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    _paginationGeneration++;
    _saveTimer?.cancel();
    unawaited(_save());
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveTimer?.cancel();
      unawaited(_save());
    }
  }

  Future<void> _restore() async {
    final chapterId = _chapter.id!;
    final prefs = await SharedPreferences.getInstance();
    final sourcePages = await LibraryDatabase.instance.loadWebChapterPages(
      chapterId,
    );
    final state = await LibraryDatabase.instance.loadWebChapterReadingState(
      chapterId,
    );
    if (!mounted || _chapter.id != chapterId) return;
    setState(() {
      _sourcePages = sourcePages;
      _showPageMarkers = prefs.getBool('showWebPageMarkers') ?? false;
      _restoreRatio = state?.progressRatio.clamp(0, 1).toDouble() ?? 0;
      _restoreAnchor = state?.paragraphAnchor;
      _restoredPosition = false;
      _layoutKey = null;
    });
  }

  void _ensurePagination(
    String text,
    ReaderSettings settings,
    Size viewport,
    TextScaler textScaler,
  ) {
    final nextKey = [
      _chapter.id,
      text.length,
      text.hashCode,
      viewport.width.toStringAsFixed(1),
      viewport.height.toStringAsFixed(1),
      textScaler.scale(1).toStringAsFixed(2),
      settings.fontFamily,
      settings.fontSize,
      settings.lineHeight,
      settings.letterSpacing,
      _showPageMarkers,
    ].join('|');
    if (_layoutKey == nextKey) return;

    if (_pageRanges.isNotEmpty && text.isNotEmpty) {
      final current = _pageRanges[_page.clamp(0, _pageRanges.length - 1)];
      _restoreRatio = current.start / text.length;
      _restoreAnchor = null;
    }

    _layoutKey = nextKey;
    final generation = ++_paginationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _paginationGeneration) {
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
      _pageRanges.clear();
      _page = 0;
      _paginationComplete = false;
      _restoredPosition = false;
    });

    var offset = 0;
    while (mounted && generation == _paginationGeneration && offset < text.length) {
      final batch = _paginationEngine.paginateBatch(
        text: text,
        startOffset: offset,
        style: settings.textStyle,
        viewport: viewport,
        textScaler: textScaler,
      );
      if (!mounted || generation != _paginationGeneration) return;
      if (batch.nextOffset <= offset) {
        throw StateError('線上小說分頁引擎未前進');
      }
      offset = batch.nextOffset;
      setState(() {
        _pageRanges.addAll(batch.pages);
        _paginationComplete = batch.isComplete;
      });
      _restoreWhenReady(text);
      await Future<void>.delayed(Duration.zero);
    }

    if (mounted && generation == _paginationGeneration && text.isEmpty) {
      setState(() => _paginationComplete = true);
    }
  }

  void _restoreWhenReady(String text) {
    if (_restoredPosition || _pageRanges.isEmpty || text.isEmpty) return;

    var targetOffset = (text.length * _restoreRatio).round();
    final anchor = _restoreAnchor;
    if (anchor != null && anchor.trim().isNotEmpty) {
      final found = text.indexOf(anchor);
      if (found >= 0) targetOffset = found;
    }

    if (!_paginationComplete && _pageRanges.last.end <= targetOffset) return;
    final targetPage = _pageRanges.indexWhere(
      (range) => targetOffset < range.end,
    );
    final index = targetPage < 0 ? _pageRanges.length - 1 : targetPage;
    _restoredPosition = true;
    _page = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(index);
        setState(() {});
      }
    });
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_chapter.id == null || _pageRanges.isEmpty) return;
    final content = _renderContent();
    if (content.isEmpty) return;
    final range = _pageRanges[_page.clamp(0, _pageRanges.length - 1)];
    final ratio = (range.start / content.length).clamp(0, 1).toDouble();
    final paragraphs = content.split(RegExp(r'\n{2,}'));
    final anchor = paragraphs.isEmpty
        ? null
        : paragraphs[((paragraphs.length - 1) * ratio).round().clamp(
            0,
            paragraphs.length - 1,
          )]
            .trim();

    await LibraryDatabase.instance.saveWebChapterReadingState(
      WebChapterReadingState(
        chapterId: _chapter.id!,
        bookId: widget.book.id,
        paragraphAnchor: anchor,
        progressRatio: ratio,
        isRead: ratio >= .9 ||
            (_paginationComplete && _page == _pageRanges.length - 1),
        lastReadAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _switch(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= widget.chapters.length || _loading) {
      return;
    }

    await _save();
    var target = widget.chapters[nextIndex];
    if (!_hasVisibleContent(target.content ?? '')) {
      setState(() => _loading = true);
      final downloader = WebChapterDownloader(
        database: LibraryDatabase.instance,
        dynamicHtmlLoader: (uri) => SafeWebViewLoader.load(context, uri),
      );
      try {
        await downloader.download(target);
        target =
            await LibraryDatabase.instance.loadWebChapter(target.id!) ?? target;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('此章尚未下載，已保留目前閱讀內容')),
          );
        }
        if (mounted) setState(() => _loading = false);
        return;
      } finally {
        downloader.close();
      }
    }

    _paginationGeneration++;
    _index = nextIndex;
    _chapter = target;
    _page = 0;
    _pageRanges.clear();
    _paginationComplete = false;
    _restoredPosition = false;
    _restoreRatio = 0;
    _restoreAnchor = null;
    _layoutKey = null;
    _loading = false;
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    if (mounted) setState(() {});
    await _restore();

    if (nextIndex + 1 < widget.chapters.length) {
      unawaited(_preload(widget.chapters[nextIndex + 1]));
    }
  }

  Future<void> _preload(WebChapter chapter) async {
    if (chapter.status != WebChapterStatus.pending) return;
    final downloader = WebChapterDownloader(
      database: LibraryDatabase.instance,
      dynamicHtmlLoader: (uri) => SafeWebViewLoader.load(context, uri),
    );
    try {
      await downloader.download(chapter);
    } catch (_) {
    } finally {
      downloader.close();
    }
  }

  String _renderContent() {
    if (!_showPageMarkers || _sourcePages.length < 2) {
      return _chapter.content ?? '';
    }
    return _sourcePages
        .where((page) => page.content != null)
        .map(
          (page) =>
              '${page.pageIndex == 0 ? '' : '—— 第 ${page.pageIndex + 1} 頁 ——\n\n'}${page.content}',
        )
        .join('\n\n');
  }

  bool _hasVisibleContent(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (sanitized.isEmpty) return false;
    return RegExp(r'[A-Za-z0-9\u3400-\u9FFF]').hasMatch(sanitized);
  }

  void _openReaderSheet() {
    final markers = [
      for (var i = 0; i < widget.chapters.length; i++)
        ChapterMarker(widget.chapters[i].title, i),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderSettingsSheet(
        chapters: markers,
        currentOffset: _index,
        onChapterSelected: (marker) => unawaited(_switch(marker.offset)),
      ),
    );
  }

  void _handleTap(double x, bool enabled) {
    if (x >= .3 && x <= .7) {
      _openReaderSheet();
      return;
    }
    if (!enabled || _pageRanges.isEmpty) return;

    if (x < .3) {
      if (_page > 0 && _pageController.hasClients) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      } else if (_index > 0) {
        unawaited(_switch(_index - 1));
      }
      return;
    }

    if (_page < _pageRanges.length - 1 && _pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else if (_paginationComplete && _index + 1 < widget.chapters.length) {
      unawaited(_switch(_index + 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final renderedContent = _renderContent();
    final hasVisibleContent = _hasVisibleContent(renderedContent);
    final textScaler = MediaQuery.textScalerOf(context);

    return Scaffold(
      backgroundColor: settings.backgroundColor,
      appBar: AppBar(
        backgroundColor: settings.backgroundColor,
        foregroundColor: settings.textColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _chapter.title,
          overflow: TextOverflow.ellipsis,
          style: webChapterTitleStyle(settings),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                _paginationComplete && _pageRanges.isNotEmpty
                    ? '${_page + 1} / ${_pageRanges.length}'
                    : '頁數計算中',
                style: TextStyle(
                  fontSize: 11,
                  color: settings.textColor.withValues(alpha: .55),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '原網頁分頁標記',
            icon: Icon(
              _showPageMarkers ? Icons.view_agenda : Icons.view_stream,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              setState(() {
                _showPageMarkers = !_showPageMarkers;
                _layoutKey = null;
              });
              await prefs.setBool('showWebPageMarkers', _showPageMarkers);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasVisibleContent
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _UnreadableChapterNotice(
                  title: _chapter.title,
                  settings: settings,
                  status: _chapter.status,
                  error: _chapter.lastError,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                const pagePadding = EdgeInsets.fromLTRB(26, 18, 26, 30);
                final pageWidth = box.maxWidth.clamp(0.0, 760.0);
                final lineSafety =
                    settings.fontSize * settings.lineHeight * 0.85;
                final viewport = Size(
                  (pageWidth - pagePadding.horizontal).clamp(1.0, 760.0),
                  (box.maxHeight - pagePadding.vertical - lineSafety).clamp(
                    1.0,
                    double.infinity,
                  ),
                );
                _ensurePagination(
                  renderedContent,
                  settings,
                  viewport,
                  textScaler,
                );

                final preparing = _pageRanges.isEmpty || !_restoredPosition;
                if (preparing) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          '正在準備閱讀頁面…',
                          style: TextStyle(
                            color: settings.textColor.withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _pointerDown = event.localPosition,
                  onPointerUp: (event) {
                    final start = _pointerDown;
                    _pointerDown = null;
                    if (start != null &&
                        (event.localPosition - start).distance < 12) {
                      _handleTap(
                        event.localPosition.dx / box.maxWidth,
                        settings.tapPageTurnEnabled,
                      );
                    }
                  },
                  onPointerCancel: (_) => _pointerDown = null,
                  child: PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.horizontal,
                    itemCount: _pageRanges.length,
                    onPageChanged: (value) {
                      setState(() => _page = value);
                      _queueSave();
                    },
                    itemBuilder: (_, pageIndex) {
                      final range = _pageRanges[pageIndex];
                      return Center(
                        child: SizedBox(
                          width: pageWidth,
                          child: Padding(
                            padding: pagePadding,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                renderedContent.substring(range.start, range.end),
                                key: ValueKey('web-reader-page-$pageIndex'),
                                style: settings.textStyle.copyWith(
                                  color: settings.textColor,
                                ),
                                textScaler: textScaler,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  TextButton.icon(
                    onPressed: _index > 0 ? () => _switch(_index - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一章'),
                  ),
                  Text('${_index + 1} / ${widget.chapters.length}'),
                  TextButton.icon(
                    onPressed: _index + 1 < widget.chapters.length
                        ? () => _switch(_index + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一章'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle webChapterTitleStyle(ReaderSettings settings) =>
    settings.textStyle.copyWith(
      color: settings.textColor,
      fontSize: settings.fontSize + 4,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );

class _UnreadableChapterNotice extends StatelessWidget {
  const _UnreadableChapterNotice({
    required this.title,
    required this.settings,
    required this.status,
    required this.error,
  });

  final String title;
  final ReaderSettings settings;
  final WebChapterStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: webChapterTitleStyle(settings)),
      const SizedBox(height: 24),
      Text(
        '本章沒有可顯示的正文內容。\n'
        '下載狀態：${status.name}${error == null ? '' : '\n錯誤：$error'}',
        key: const ValueKey('web-chapter-unreadable'),
        style: settings.textStyle.copyWith(color: settings.textColor),
      ),
    ],
  );
}
