import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/library_database.dart';
import '../../core/services/web_chapter_downloader.dart';
import '../../core/services/safe_webview_loader.dart';
import '../reader/domain/reader_models.dart';
import '../reader/presentation/reader_controller.dart';
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
  final _scroll = ScrollController();
  Timer? _saveTimer;
  late int _index = widget.chapters.indexWhere((chapter) => chapter.id == widget.initialChapterId).clamp(0, widget.chapters.length - 1).toInt();
  late WebChapter _chapter = widget.chapters[_index];
  bool _loading = false;
  bool _showPageMarkers = false;
  List<WebChapterPage> _pages = const [];
  int _restoreGeneration = 0;

  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _scroll.addListener(_scheduleSave); _restore(); }
  @override void dispose() { _save(); _saveTimer?.cancel(); _scroll.dispose(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _save(); }

  Future<void> _restore() async {
    final generation = ++_restoreGeneration;
    final chapterId = _chapter.id!;
    final prefs = await SharedPreferences.getInstance();
    final state = await LibraryDatabase.instance.loadWebChapterReadingState(chapterId);
    final pages = await LibraryDatabase.instance.loadWebChapterPages(chapterId);
    if (!mounted || generation != _restoreGeneration || _chapter.id != chapterId) return;
    setState(() { _pages = pages; _showPageMarkers = prefs.getBool('showWebPageMarkers') ?? false; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _restoreGeneration || !_scroll.hasClients || state == null) return;
      final content = _chapter.content ?? '';
      final anchor = state.paragraphAnchor;
      final anchorOffset = anchor == null || anchor.isEmpty ? -1 : content.indexOf(anchor);
      final ratio = anchorOffset >= 0 && content.isNotEmpty ? anchorOffset / content.length : state.progressRatio;
      _scroll.jumpTo(_scroll.position.maxScrollExtent * ratio.clamp(0, 1));
    });
  }

  void _scheduleSave() { _saveTimer?.cancel(); _saveTimer = Timer(const Duration(seconds: 1), _save); }
  Future<void> _save() async {
    if (!_scroll.hasClients || _chapter.id == null) return;
    final ratio = _scroll.position.maxScrollExtent <= 0 ? 1.0 : (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0, 1).toDouble();
    final content = _chapter.content ?? '';
    final paragraphs = content.split(RegExp(r'\n{2,}'));
    final anchor = paragraphs.isEmpty ? null : paragraphs[((paragraphs.length - 1) * ratio).round().clamp(0, paragraphs.length - 1)].trim();
    await LibraryDatabase.instance.saveWebChapterReadingState(WebChapterReadingState(
      chapterId: _chapter.id!, bookId: widget.book.id, paragraphAnchor: anchor,
      progressRatio: ratio, isRead: ratio >= .9, lastReadAt: DateTime.now().toUtc(),
    ));
  }

  Future<void> _switch(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= widget.chapters.length || _loading) return;
    await _save();
    var target = widget.chapters[nextIndex];
    if (target.content?.trim().isEmpty ?? true) {
      setState(() => _loading = true);
      final downloader = WebChapterDownloader(
          database: LibraryDatabase.instance,
          dynamicHtmlLoader: (uri) => SafeWebViewLoader.load(context, uri),
        );
      try {
        await downloader.download(target);
        target = await LibraryDatabase.instance.loadWebChapter(target.id!) ?? target;
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此章尚未下載，已保留目前閱讀內容')));
        setState(() => _loading = false);
        return;
      } finally { downloader.close(); }
    }
    _index = nextIndex; _chapter = target; _loading = false;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _restore();
    if (nextIndex + 1 < widget.chapters.length) unawaited(_preload(widget.chapters[nextIndex + 1]));
  }

  Future<void> _preload(WebChapter chapter) async {
    if (chapter.status != WebChapterStatus.pending) return;
    final downloader = WebChapterDownloader(
      database: LibraryDatabase.instance,
      dynamicHtmlLoader: (uri) => SafeWebViewLoader.load(context, uri),
    );
    try { await downloader.download(chapter); } catch (_) {} finally { downloader.close(); }
  }

  String _renderContent() {
    if (!_showPageMarkers || _pages.length < 2) return _chapter.content ?? '';
    return _pages.where((p) => p.content != null).map((p) => '${p.pageIndex == 0 ? '' : '—— 第 ${p.pageIndex + 1} 頁 ——\n\n'}${p.content}').join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    return Scaffold(
      backgroundColor: settings.backgroundColor,
      appBar: AppBar(
        backgroundColor: settings.backgroundColor,
        foregroundColor: settings.textColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _chapter.title,
          style: webChapterTitleStyle(settings),
        ),
        actions: [
          IconButton(
            tooltip: '原網頁分頁標記',
            icon: Icon(
              _showPageMarkers ? Icons.view_agenda : Icons.view_stream,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              setState(() => _showPageMarkers = !_showPageMarkers);
              await prefs.setBool('showWebPageMarkers', _showPageMarkers);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SelectionArea(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                child: WebChapterBody(
                  title: _chapter.title,
                  content: _renderContent(),
                  settings: settings,
                  isPartial: _chapter.status == WebChapterStatus.partial,
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
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
    );
  }
}

TextStyle webChapterTitleStyle(ReaderSettings settings) =>
    settings.textStyle.copyWith(
      fontSize: settings.fontSize + 4,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );

class WebChapterBody extends StatelessWidget {
  const WebChapterBody({
    super.key,
    required this.title,
    required this.content,
    required this.settings,
    required this.isPartial,
  });

  final String title;
  final String content;
  final ReaderSettings settings;
  final bool isPartial;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        key: const ValueKey('web-chapter-title'),
        style: webChapterTitleStyle(settings),
      ),
      const SizedBox(height: 24),
      Text(
        content,
        key: const ValueKey('web-chapter-content'),
        style: settings.textStyle,
      ),
      if (isPartial)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: Text(
            '本章下載不完整',
            style: TextStyle(color: Colors.orange),
          ),
        ),
    ],
  );
}
