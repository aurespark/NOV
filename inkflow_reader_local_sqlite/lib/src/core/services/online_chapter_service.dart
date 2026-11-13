import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'novel_html_extractor.dart';

class OnlineChapterService {
  static const _maxSubPages = 20;
  final Database db;
  OnlineChapterService({required this.db});

  static String extractText(String html) => ChapterContentExtractor.extractText(html);

  Future<String> getChapterText({
    required String bookId,
    required int chapterIndex,
    required String chapterUrl,
    required Future<String> Function(String url) fetcher,
  }) async {
    debugPrint('[ContentFetch] 🔍 檢查快取: 書籍 $bookId, 第 ${chapterIndex + 1} 章');

    try {
      final rows = await db.query(
        'chapters',
        columns: ['content'],
        where: 'bookId = ? AND chapterIndex = ?',
        whereArgs: [bookId, chapterIndex],
        limit: 1,
      );
      if (rows.isNotEmpty && rows.first['content'] is String && (rows.first['content'] as String).isNotEmpty) {
        final text = rows.first['content'] as String;
        debugPrint('[ContentFetch] ✅ 本地快取命中: 第 ${chapterIndex + 1} 章 (${text.length} 字)');
        return text;
      }
    } catch (e) {
      debugPrint('[ContentFetch] ⚠️ 快取查詢略過: $e');
    }

    debugPrint('[ContentFetch] 🌐 開始線上抓取正文: $chapterUrl');
    // 同章分頁（123_2.html…）逐頁合併；中途失敗則回傳已取得部分且不寫快取
    final parts = <String>[];
    final seen = <String>{};
    var url = chapterUrl;
    var complete = true;
    while (seen.add(url) && seen.length <= _maxSubPages) {
      final String rawHtml;
      try {
        rawHtml = await fetcher(url);
      } catch (e) {
        debugPrint('[ContentFetch] ❌ 網路抓取失敗: $url $e');
        complete = false;
        break;
      }
      final part = extractText(rawHtml);
      if (part.isNotEmpty) parts.add(part);
      final next = ChapterContentExtractor.findNextPageUrl(rawHtml, url);
      if (next == null) break;
      debugPrint('[ContentFetch] ➡️ 同章下一頁: $next');
      url = next;
    }

    final text = parts.join('\n\n');
    if (text.isEmpty) {
      debugPrint('[ContentFetch] ⚠️ 警告: 抓取正文為空');
      return complete ? '（本章內容為空或解析失敗）' : '（網路連線失敗，請檢查網路或稍後重試）';
    }
    if (!complete) return text;

    try {
      await db.update(
        'chapters',
        {'content': text},
        where: 'bookId = ? AND chapterIndex = ?',
        whereArgs: [bookId, chapterIndex],
      );
      debugPrint('[ContentFetch] 💾 正文寫入快取成功: 第 ${chapterIndex + 1} 章 (${text.length} 字)');
    } catch (e) {
      debugPrint('[ContentFetch] ⚠️ 寫入 SQLite 快取失敗: $e');
    }

    return text;
  }
}
