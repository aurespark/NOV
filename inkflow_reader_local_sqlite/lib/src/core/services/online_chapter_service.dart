import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class OnlineChapterService {
  final Database db;
  OnlineChapterService({required this.db});

  // ponytail: 三引號 Raw String 杜絕單引號跳脫問題；正則提取 div.content 省去 heavy DOM 依賴
  static String extractText(String html) {
    if (html.isEmpty) return '';
    final match = RegExp(r"""<div[^>]*class=["']content["'][^>]*>([\s\S]*?)</div>""", caseSensitive: false)
        .firstMatch(html);
    final raw = match?.group(1) ?? html;
    return raw
        .replaceAll(RegExp(r"""<script[\s\S]*?</script>|<style[\s\S]*?</style>|<ins[\s\S]*?</ins>""", caseSensitive: false), '')
        .replaceAll(RegExp(r"""<br\s*/?>""", caseSensitive: false), '\n')
        .replaceAll(RegExp(r"""</p>""", caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r"""<[^>]+>"""), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

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
        where: 'book_id = ? AND chapter_index = ?',
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
    String rawHtml = '';
    try {
      rawHtml = await fetcher(chapterUrl);
    } catch (e) {
      debugPrint('[ContentFetch] ❌ 網路抓取失敗: $e');
      return '（網路連線失敗，請檢查網路或稍後重試）';
    }

    final text = extractText(rawHtml);
    if (text.isEmpty) {
      debugPrint('[ContentFetch] ⚠️ 警告: 抓取正文為空');
      return '（本章內容為空或解析失敗）';
    }

    try {
      await db.update(
        'chapters',
        {'content': text},
        where: 'book_id = ? AND chapter_index = ?',
        whereArgs: [bookId, chapterIndex],
      );
      debugPrint('[ContentFetch] 💾 正文寫入快取成功: 第 ${chapterIndex + 1} 章 (${text.length} 字)');
    } catch (e) {
      debugPrint('[ContentFetch] ⚠️ 寫入 SQLite 快取失敗: $e');
    }

    return text;
  }
}
