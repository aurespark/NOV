import 'package:flutter/material.dart';

import '../../core/services/library_database.dart';
import '../../core/services/web_chapter_downloader.dart';
import '../../core/services/safe_webview_loader.dart';
import 'book.dart';
import 'web_chapter_reader_view.dart';
import 'web_novel_models.dart';

class WebChapterListView extends StatefulWidget {
  const WebChapterListView({super.key, required this.book, required this.chapters});
  final Book book;
  final List<WebChapter> chapters;

  @override
  State<WebChapterListView> createState() => _WebChapterListViewState();
}

class _WebChapterListViewState extends State<WebChapterListView> {
  late List<WebChapter> _chapters = widget.chapters;
  bool _busy = false;

  Future<void> _open(WebChapter chapter) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var current = chapter;
      if (chapter.status != WebChapterStatus.complete && chapter.status != WebChapterStatus.partial) {
        final downloader = WebChapterDownloader(
          database: LibraryDatabase.instance,
          dynamicHtmlLoader: (uri) => SafeWebViewLoader.load(context, uri),
        );
        await downloader.download(chapter);
        current = await LibraryDatabase.instance.loadWebChapter(chapter.id!) ?? chapter;
        _chapters = await LibraryDatabase.instance.loadWebChapters(widget.book.id);
      }
      if (!mounted) return;
      if (current.content?.trim().isEmpty ?? true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(current.lastError ?? '此章尚未下載')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebChapterReaderView(
        book: widget.book, chapters: _chapters, initialChapterId: current.id!,
      )));
      _chapters = await LibraryDatabase.instance.loadWebChapters(widget.book.id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下載失敗：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.book.title), actions: [
      PopupMenuButton<String>(onSelected: (value) async {
        if (value == 'clearIncomplete') await LibraryDatabase.instance.clearIncompleteWebCache(widget.book.id);
        if (value == 'clearAll') await LibraryDatabase.instance.clearWebBookDownloads(widget.book.id);
        _chapters = await LibraryDatabase.instance.loadWebChapters(widget.book.id);
        if (mounted) setState(() {});
      }, itemBuilder: (_) => const [
        PopupMenuItem(value: 'clearIncomplete', child: Text('清除失敗與部分下載')),
        PopupMenuItem(value: 'clearAll', child: Text('清除下載內容（保留書籍）')),
      ]),
    ]),
    body: _chapters.isEmpty
        ? const Center(child: Text('此書沒有找到任何章節'))
        : ListView.builder(
            itemCount: _chapters.length,
            itemBuilder: (context, index) {
              final chapter = _chapters[index];
              return ListTile(
                leading: Icon(_statusIcon(chapter.status), color: _statusColor(context, chapter.status)),
                title: Text(chapter.title),
                subtitle: Text([
                  _statusLabel(chapter.status),
                  if (chapter.isSourceRemoved) '來源已移除',
                ].join(' · ')),
                trailing: _busy ? null : const Icon(Icons.chevron_right),
                onTap: () => _open(chapter),
              );
            },
          ),
  );

  IconData _statusIcon(WebChapterStatus status) => switch (status) {
    WebChapterStatus.complete => Icons.offline_pin,
    WebChapterStatus.partial => Icons.warning_amber,
    WebChapterStatus.downloading => Icons.downloading,
    WebChapterStatus.blocked => Icons.lock_outline,
    WebChapterStatus.failed => Icons.error_outline,
    WebChapterStatus.pending => Icons.cloud_download_outlined,
  };
  Color _statusColor(BuildContext context, WebChapterStatus status) => switch (status) {
    WebChapterStatus.complete => Colors.green,
    WebChapterStatus.partial => Colors.orange,
    WebChapterStatus.failed || WebChapterStatus.blocked => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.primary,
  };
  String _statusLabel(WebChapterStatus status) => switch (status) {
    WebChapterStatus.complete => '已下載', WebChapterStatus.partial => '部分下載',
    WebChapterStatus.downloading => '下載中', WebChapterStatus.blocked => '存取受限',
    WebChapterStatus.failed => '下載失敗', WebChapterStatus.pending => '尚未下載',
  };
}
