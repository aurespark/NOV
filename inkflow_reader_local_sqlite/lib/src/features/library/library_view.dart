import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/book_file_store.dart';
import '../../core/services/encoding_service.dart';
import '../../core/services/library_database.dart';
import '../../core/services/web_catalog_resolver.dart';
import '../../core/services/web_url_policy.dart';
import 'web_catalog_import_dialog.dart';
import '../reader/domain/reader_models.dart';
import '../reader/presentation/reader_controller.dart';
import '../reader/presentation/reader_view.dart';
import 'book.dart';
import 'web_novel_models.dart';
import 'web_chapter_list_view.dart';

enum _BookAction { edit, toggleFinished, remove }

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});
  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  final searchController = TextEditingController();
  final List<Book> books = [];
  BookSort sort = BookSort.lastRead;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() => loading = true);
    try {
      final saved = await LibraryDatabase.instance.loadBooks();
      if (mounted) setState(() => books.addAll(saved));
    } catch (error) {
      _message('無法載入書架：$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Book> get visibleBooks {
    final keyword = searchController.text.trim().toLowerCase();
    final result = books
        .where(
          (book) =>
              keyword.isEmpty ||
              book.title.toLowerCase().contains(keyword) ||
              book.author.toLowerCase().contains(keyword),
        )
        .toList();
    switch (sort) {
      case BookSort.lastRead:
        result.sort(
          (a, b) => (b.lastReadAt ?? b.createdAt).compareTo(
            a.lastReadAt ?? a.createdAt,
          ),
        );
        break;
      case BookSort.title:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case BookSort.progress:
        result.sort((a, b) => b.progressRatio.compareTo(a.progressRatio));
        break;
    }
    return result;
  }

  Future<void> _importLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: false,
    );
    if (result == null) return;
    setState(() => loading = true);
    String? savedPath;
    try {
      final picked = result.files.single;
      if (p.extension(picked.name).toLowerCase() != '.txt') {
        throw const FormatException('只能匯入 TXT 檔案');
      }
      final sourcePath = picked.path;
      if (sourcePath == null) {
        throw const FileSystemException('行動版無法取得所選 TXT 的檔案路徑');
      }
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      savedPath = await BookFileStore().importTxt(sourcePath, id);
      final file = File(savedPath);
      final bytes = await file.readAsBytes();
      final encodingService = EncodingService();
      var decoded = await encodingService.decode(bytes);
      if (!decoded.confident && mounted) {
        final encoding = await _chooseEncoding();
        if (encoding == null) {
          await BookFileStore().delete(savedPath);
          savedPath = null;
          return;
        }
        if (encoding != TextEncoding.auto) {
          decoded = await encodingService.decode(bytes, encoding);
        }
      }
      final title = p.basenameWithoutExtension(picked.name);
      final book = Book(
        id: id,
        title: title,
        author: '未知作者',
        sourceType: BookSourceType.local,
        localPath: savedPath,
        textEncoding: decoded.encoding.name,
        fileSize: await file.length(),
        characterOffset: 0,
        currentChapter: '',
        progressRatio: 0,
        createdAt: DateTime.now(),
        isFinished: false,
      );
      final chapters = ChapterParser.parse(decoded.text);
      await LibraryDatabase.instance.insertBook(book, localChapters: chapters);
      savedPath = null;
      if (!mounted) return;
      setState(() => books.insert(0, book));
      await _open(book, initialText: decoded.text);
    } catch (error) {
      if (savedPath != null) await BookFileStore().delete(savedPath);
      _message('匯入失敗：$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<TextEncoding?> _chooseEncoding() {
    const labels = {
      TextEncoding.auto: '自動（目前判斷為 Big5）',
      TextEncoding.big5: 'Big5／繁體中文 ANSI',
      TextEncoding.gbk: 'GBK／簡體中文 ANSI',
      TextEncoding.utf8: 'UTF-8',
      TextEncoding.utf16le: 'UTF-16 LE',
      TextEncoding.utf16be: 'UTF-16 BE',
    };
    return showDialog<TextEncoding>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('選擇 TXT 編碼'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text('無法完全確認這個檔案的編碼。若上次顯示亂碼，請改選 Big5 或 GBK。'),
          ),
          for (final encoding in TextEncoding.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, encoding),
              child: Text(labels[encoding] ?? encoding.name),
            ),
        ],
      ),
    );
  }

  Future<void> _addWeb() async {
    final submitted = await showWebCatalogUrlDialog(context);
    if (!mounted || submitted == null) return;

    const urlPolicy = WebUrlPolicy();
    late final Uri uri;
    try {
      uri = urlPolicy.parseAndNormalize(submitted);
    } on FormatException catch (error) {
      _message(error.message);
      return;
    }

    final existing = books.where((book) {
      if (book.sourceType != BookSourceType.web || book.catalogUrl == null) {
        return false;
      }
      try {
        return urlPolicy.parseAndNormalize(book.catalogUrl!) == uri;
      } on FormatException {
        return false;
      }
    }).firstOrNull;
    if (existing != null) {
      await _showExistingWebBook(existing);
      return;
    }

    setState(() => loading = true);
    try {
      final resolution = await WebCatalogResolver(
        urlPolicy: urlPolicy,
      ).resolve(uri);
      final links = resolution.bestCluster?.links ?? const <WebCatalogLink>[];
      if (links.isEmpty) {
        if (resolution.diagnostics.completeness ==
            WebCatalogCompleteness.fallbackRequired) {
          await _showCatalogFallback(resolution);
          return;
        }
        throw const WebCatalogException('找不到可信的章節目錄，未建立書籍');
      }
      final title = _normalizeWebTitle(resolution.pageTitle ?? uri.host);
      final confirmed = await _confirmWebImport(
        title: title,
        sourceHost: resolution.url.host,
        chapterCount: links.length,
        warnings: resolution.warnings,
        diagnostics: resolution.diagnostics,
      );
      if (!mounted || !confirmed) return;

      // Recheck immediately before writing so rapid repeated submissions cannot
      // create a duplicate source in this process.
      final duplicate = books.where((book) {
        if (book.sourceType != BookSourceType.web || book.catalogUrl == null) {
          return false;
        }
        try {
          return urlPolicy.parseAndNormalize(book.catalogUrl!) ==
              urlPolicy.normalize(resolution.url);
        } on FormatException {
          return false;
        }
      }).firstOrNull;
      if (duplicate != null) {
        await _showExistingWebBook(duplicate);
        return;
      }

      final book = Book(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        author: '網路書籍',
        sourceType: BookSourceType.web,
        catalogUrl: urlPolicy.normalize(resolution.url).toString(),
        catalogSelector: resolution.bestSelector,
        characterOffset: 0,
        currentChapter: '',
        progressRatio: 0,
        createdAt: DateTime.now(),
        isFinished: false,
      );
      final chapters = [
        for (var i = 0; i < links.length; i++)
          WebChapter(
            url: links[i].href.toString(),
            normalizedUrl: urlPolicy.normalize(links[i].href).toString(),
            title: links[i].text,
            position: i,
          ),
      ];
      await LibraryDatabase.instance.insertBook(book, webChapters: chapters);
      if (!mounted) return;
      setState(() => books.insert(0, book));
      _message('已匯入《${book.title}》，共 ${chapters.length} 章。');
    } catch (error) {
      _message('匯入線上小說失敗：$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _confirmWebImport({
    required String title,
    required String sourceHost,
    required int chapterCount,
    required List<String> warnings,
    required WebCatalogDiagnostics diagnostics,
  }) async {
    final isComplete =
        diagnostics.completeness == WebCatalogCompleteness.complete;
    final completenessLabel = switch (diagnostics.completeness) {
      WebCatalogCompleteness.complete => '完整性：高信心完整',
      WebCatalogCompleteness.warning => '完整性：可能不完整',
      WebCatalogCompleteness.fallbackRequired => '完整性：需要動態解析',
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認匯入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('來源：$sourceHost'),
            Text('章節：$chapterCount 章'),
            Text('已檢查目錄頁：${diagnostics.visitedPages} 頁'),
            Text(
              completenessLabel,
              style: TextStyle(
                color: isComplete
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in warnings)
                Text(
                  '• $warning',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認匯入'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showCatalogFallback(WebCatalogResolution resolution) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要動態解析'),
        content: Text(
          '已檢查 ${resolution.diagnostics.visitedPages} 頁，但靜態網頁沒有提供完整目錄。'
          '此網站需要 M7 的安全 WebView 備援，目前不會建立不完整書籍。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExistingWebBook(Book book) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('此來源已存在'),
        content: Text('《${book.title}》已在書架中，不會建立重複書籍。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: const Text('更新目錄'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'open'),
            child: const Text('開啟現有書籍'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'open') {
      await _open(book);
    } else if (action == 'update') {
      _message('目錄更新將於 M5 啟用，目前未新增副本。');
    }
  }

  Future<void> _open(Book book, {String? initialText}) async {
    if (book.sourceType == BookSourceType.web) {
      final chapters = await LibraryDatabase.instance.loadWebChapters(book.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WebChapterListView(book: book, chapters: chapters),
        ),
      );
      return;
    }
    final path = book.localPath;
    if (path == null || !await File(path).exists()) {
      _message('找不到《${book.title}》的本機 TXT 檔案');
      return;
    }
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final encoding = TextEncoding.values.firstWhere(
        (value) => value.name == book.textEncoding,
        orElse: () => TextEncoding.auto,
      );
      final text =
          initialText ??
          (await EncodingService().decode(
            await File(path).readAsBytes(),
            encoding,
          )).text;
      var chapters = await LibraryDatabase.instance.loadChapters(book.id);
      if (chapters.isEmpty) {
        chapters = ChapterParser.parse(text);
        await LibraryDatabase.instance.replaceChapters(book.id, chapters);
      }
      if (!mounted) return;
      ref.read(bookTextProvider.notifier).set(text);
      ref.read(bookTitleProvider.notifier).set(book.title);
      final updated = await Navigator.of(context).push<Book>(
        MaterialPageRoute(
          builder: (_) => ReaderView(book: book, chapters: chapters),
        ),
      );
      if (updated != null && mounted) {
        setState(() {
          final index = books.indexWhere((item) => item.id == updated.id);
          if (index >= 0) books[index] = updated;
        });
      }
    } catch (error) {
      _message('無法開啟《${book.title}》：$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _manage(Book book) async {
    final action = await showModalBottomSheet<_BookAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯書名與作者'),
              onTap: () => Navigator.pop(context, _BookAction.edit),
            ),
            ListTile(
              leading: Icon(
                book.isFinished
                    ? Icons.restart_alt_rounded
                    : Icons.done_all_rounded,
              ),
              title: Text(book.isFinished ? '標示為未讀' : '標示為已讀'),
              onTap: () => Navigator.pop(context, _BookAction.toggleFinished),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('從書架刪除'),
              onTap: () => Navigator.pop(context, _BookAction.remove),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _BookAction.edit:
        await _edit(book);
        break;
      case _BookAction.toggleFinished:
        final updated = book.copyWith(
          isFinished: !book.isFinished,
          progressRatio: book.isFinished ? 0 : 1,
          characterOffset: book.isFinished ? 0 : book.characterOffset,
          lastReadAt: DateTime.now(),
        );
        await LibraryDatabase.instance.updateBook(updated);
        await LibraryDatabase.instance.saveProgress(updated);
        if (mounted) _replace(updated);
        break;
      case _BookAction.remove:
        final message = book.localPath == null
            ? '將《${book.title}》從書架刪除？'
            : '將《${book.title}》與本機檔案一併刪除？';
        if (await _confirm(message)) {
          await LibraryDatabase.instance.deleteBook(book.id);
          await BookFileStore().delete(book.localPath);
          if (mounted) {
            setState(() => books.removeWhere((item) => item.id == book.id));
          }
        }
        break;
    }
  }

  Future<void> _edit(Book book) async {
    final title = TextEditingController(text: book.title);
    final author = TextEditingController(text: book.author);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯書籍資訊'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '書名'),
            ),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: '作者'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (confirmed == true && title.text.trim().isNotEmpty) {
      final updated = book.copyWith(
        title: title.text.trim(),
        author: author.text.trim().isEmpty ? '未知作者' : author.text.trim(),
      );
      await LibraryDatabase.instance.updateBook(updated);
      if (mounted) _replace(updated);
    }
  }

  void _replace(Book updated) {
    setState(() {
      final index = books.indexWhere((book) => book.id == updated.id);
      if (index >= 0) books[index] = updated;
    });
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('確認操作'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleBooks;
    return Scaffold(
      backgroundColor: const Color(0xff000000),
      floatingActionButton: books.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showImportMenu,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增書籍'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '墨讀',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: Color(0xfff4f1ea),
                          ),
                        ),
                        Text(
                          '你的私人書架',
                          style: TextStyle(
                            color: Color(0xffa6a09a),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<BookSort>(
                    tooltip: '排序',
                    initialValue: sort,
                    onSelected: (value) => setState(() => sort = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: BookSort.lastRead,
                        child: Text('最後閱讀時間'),
                      ),
                      PopupMenuItem(value: BookSort.title, child: Text('書名')),
                      PopupMenuItem(
                        value: BookSort.progress,
                        child: Text('閱讀進度'),
                      ),
                    ],
                    icon: const Icon(Icons.sort_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜尋書名或作者',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xff151515),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: books.isEmpty && !loading
                  ? _EmptyShelf(onImport: _showImportMenu)
                  : visible.isEmpty
                  ? const Center(
                      child: Text(
                        '找不到符合的書籍',
                        style: TextStyle(color: Color(0xffd8d8d8)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 100),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final book = visible[index];
                        return Dismissible(
                          key: ValueKey(book.id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            await _manage(book);
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 26),
                            decoration: BoxDecoration(
                              color: const Color(0xff2a2a2a),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.more_horiz,
                              color: Color(0xfff2f2f2),
                            ),
                          ),
                          child: _BookTile(
                            book: book,
                            onTap: () => _open(book),
                            onLongPress: () => _manage(book),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportMenu() async {
    final source = await showModalBottomSheet<BookSourceType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('匯入本地 TXT'),
              subtitle: const Text('複製到 App 私人目錄並永久保留'),
              onTap: () => Navigator.pop(context, BookSourceType.local),
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('新增網路書籍'),
              subtitle: const Text('只需輸入目錄 URL'),
              onTap: () => Navigator.pop(context, BookSourceType.web),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == BookSourceType.local) await _importLocal();
    if (source == BookSourceType.web) await _addWeb();
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final percent = (book.progressRatio.clamp(0, 1) * 100).round();
    return Material(
      color: const Color(0xff141414),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookCover(book: book),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xfff3f3f3),
                            ),
                          ),
                        ),
                        if (book.isFinished)
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xff8db89d),
                            size: 19,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xffb3b3b3)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: book.sourceType == BookSourceType.local
                                ? const Color(0xff2d241d)
                                : const Color(0xff1d2a26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            book.sourceType == BookSourceType.local
                                ? '本地 TXT'
                                : '網路',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xfff3f3f3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: book.progressRatio.clamp(0, 1),
                        minHeight: 5,
                        color: const Color(0xff8d7b6a),
                        backgroundColor: const Color(0xff2a2a2a),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _lastRead(book.lastReadAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff8f8f8f),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _lastRead(DateTime? value) {
    if (value == null) return '尚未閱讀';
    final now = DateTime.now();
    final local = value.toLocal();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) return '剛剛閱讀';
    if (difference.inHours < 1) return '${difference.inMinutes} 分鐘前閱讀';
    if (difference.inDays < 1) return '${difference.inHours} 小時前閱讀';
    if (difference.inDays < 7) return '${difference.inDays} 天前閱讀';
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} 閱讀';
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});
  final Book book;
  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.file(File(path), width: 64, height: 88, fit: BoxFit.cover),
      );
    }
    final label = book.title.trim().isEmpty
        ? '書'
        : book.title.trim().characters.take(2).toString();
    return Container(
      width: 64,
      height: 88,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: book.sourceType == BookSourceType.local
            ? const Color(0xff4c3a2f)
            : const Color(0xff3b4c46),
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(2, 4)),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xfff2f2f2),
          fontFamily: 'serif',
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onImport});
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 72,
            color: Color(0xff6f6f6f),
          ),
          const SizedBox(height: 20),
          const Text(
            '書架還是空的',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xfff2f2f2),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '匯入 TXT，或先保存一本網路書籍',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xffa8a8a8)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增第一本書'),
          ),
        ],
      ),
    ),
  );
}
