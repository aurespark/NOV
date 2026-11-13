import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/services/novel_html_extractor.dart';
import '../../../core/services/online_chapter_service.dart';
import '../domain/reader_models.dart';
import 'reader_controller.dart';
import 'reader_view.dart';

// GBK/Big5 站點需依 charset 解碼，改用共用下載器
Future<String> defaultHtmlFetcher(String url) => fetchNovelHtml(url);

Future<void> openChapterInReader({
  required BuildContext context,
  required WidgetRef ref,
  required dynamic book,
  required List<ChapterMarker> chapters,
  required int chapterIndex,
  required Database db,
  Future<String> Function(String)? htmlFetcher,
}) async {
  final title = chapterIndex < chapters.length ? chapters[chapterIndex].title : '第 ${chapterIndex + 1} 章';
  final bookId = (book.id ?? '').toString();
  final bookTitle = (book.title ?? '').toString();
  
  debugPrint('[LibraryNav] 📑 使用者點選章節: 第 ${chapterIndex + 1} 章 ($title)');

  // 1. 取得該章節的 URL
  final dynamic ch = chapterIndex < chapters.length ? chapters[chapterIndex] : null;
  String url = '';
  try {
    url = (ch?.url ?? ch?.link ?? '').toString();
  } catch (_) {}

  // 2. 透過階段一的快取服務取得正文
  final service = OnlineChapterService(db: db);
  final content = await service.getChapterText(
    bookId: bookId,
    chapterIndex: chapterIndex,
    chapterUrl: url,
    fetcher: htmlFetcher ?? defaultHtmlFetcher,
  );

  // 3. 注入現有的 Riverpod Provider (完全維持你原有的 reader_view 排版)
  ref.read(bookTextProvider.notifier).set(content);
  ref.read(bookTitleProvider.notifier).set('$bookTitle - $title');
  debugPrint('[LibraryNav] 🚀 正文注入完畢 (長度: ${content.length} 字)，推入原生閱讀介面');

  if (!context.mounted) return;

  // 4. 推入原生 ReaderView
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReaderView(book: book, chapters: chapters),
    ),
  );
}
