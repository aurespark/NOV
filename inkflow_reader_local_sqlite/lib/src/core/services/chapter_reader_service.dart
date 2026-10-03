import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

/// 閱讀模式列舉
enum ReadingMode {
  nativeText,
  webView,
}

/// 章節內容回傳結果
class ChapterContentResult {
  final int chapterIndex;
  final String title;
  final String content;
  final String chapterUrl;
  final ReadingMode mode;
  final bool isFromCache;

  ChapterContentResult({
    required this.chapterIndex,
    required this.title,
    required this.content,
    required this.chapterUrl,
    required this.mode,
    required this.isFromCache,
  });

  Map<String, dynamic> toMap() {
    return {
      'chapterIndex': chapterIndex,
      'title': title,
      'content': content,
      'chapterUrl': chapterUrl,
      'mode': mode.name,
      'isFromCache': isFromCache ? 1 : 0,
    };
  }

  factory ChapterContentResult.fromMap(Map<String, dynamic> map) {
    return ChapterContentResult(
      chapterIndex: map['chapterIndex'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      chapterUrl: map['chapterUrl'] as String? ?? '',
      mode: map['mode'] == 'webView' ? ReadingMode.webView : ReadingMode.nativeText,
      isFromCache: (map['isFromCache'] as int? ?? 0) == 1,
    );
  }
}

class ChapterReaderService {
  // 單例模式 (Singleton)
  static final ChapterReaderService instance = ChapterReaderService._internal();

  factory ChapterReaderService() => instance;

  ChapterReaderService._internal();

  // 靜態屬性供 WebReadView 等畫面存取
  static String? sharedUserAgent;
  static String sharedCookies = '';

  Database? _db;

  void setDatabase(Database database) {
    _db = database;
  }

  /// 從 SQLite 讀取快取章節
  Future<Map<String, dynamic>?> getChapterFromDb(String url, {String? bookId, int? chapterIndex}) async {
    if (_db == null) return null;
    try {
      final List<Map<String, dynamic>> results;
      if (url.isNotEmpty) {
        results = await _db!.query(
          'chapters',
          where: 'url = ?',
          whereArgs: [url],
          limit: 1,
        );
      } else if (bookId != null && chapterIndex != null) {
        results = await _db!.query(
          'chapters',
          where: 'bookId = ? AND chapterIndex = ?',
          whereArgs: [bookId, chapterIndex],
          limit: 1,
        );
      } else {
        return null;
      }

      if (results.isNotEmpty) {
        return results.first;
      }
    } catch (e) {
      debugPrint('[ChapterReaderService] 查詢快取失敗: $e');
    }
    return null;
  }

  /// 儲存章節資料至本地 SQLite 快取
  Future<void> saveChapterToDb({
    required String url,
    required String title,
    required String content,
    required int chapterIndex,
    String? bookId,
  }) async {
    if (_db == null) return;
    try {
      await dbSaveLogic(
        url: url,
        title: title,
        content: content,
        chapterIndex: chapterIndex,
        bookId: bookId,
      );
    } catch (e) {
      debugPrint('[ChapterReaderService] 寫入快取失敗: $e');
    }
  }

  Future<void> dbSaveLogic({
    required String url,
    required String title,
    required String content,
    required int chapterIndex,
    String? bookId,
  }) async {
    await _db!.insert(
      'chapters',
      {
        'url': url,
        'title': title,
        'content': content,
        'chapterIndex': chapterIndex,
        if (bookId != null) 'bookId': bookId,
        'isSaved': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 載入章節核心方法
  Future<ChapterContentResult> loadChapter({
    String? bookId,
    required int chapterIndex,
    String? title,
    String? url,
    bool forceRefresh = false,
  }) async {
    final effectiveUrl = url ?? '';
    final effectiveTitle = title ?? '第 ${chapterIndex + 1} 章';

    final chapterData = await getChapterFromDb(
      effectiveUrl,
      bookId: bookId,
      chapterIndex: chapterIndex,
    );

    // 1. 檢查本地 SQLite 快取：只要 content 有實質文字（>= 80 字），就是 100% 快取命中！
    final cachedContent = chapterData?['content'] as String?;
    if (!forceRefresh && cachedContent != null && cachedContent.trim().length >= 80) {
      debugPrint(
          '[ChapterReaderService] ✅ SQLite 快取命中: 第 ${chapterIndex + 1} 章 (${cachedContent.length} 字)，秒開！');
      return ChapterContentResult(
        chapterIndex: chapterIndex,
        title: effectiveTitle,
        content: cachedContent,
        chapterUrl: effectiveUrl,
        mode: ReadingMode.nativeText,
        isFromCache: true,
      );
    }

    if (effectiveUrl.isEmpty) {
      throw Exception('章節 URL 為空且無本地快取可用');
    }

    // 2. 背景發起網路請求：補上 Referer 防盜鏈與 User-Agent
    final headers = <String, String>{
      'User-Agent': sharedUserAgent ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': effectiveUrl.contains('po18')
          ? 'https://wap.po18.in/'
          : 'https://czbooks.net/', // 👈 補上防盜鏈 Referer
    };
    if (sharedCookies.isNotEmpty) {
      headers['Cookie'] = sharedCookies;
    }

    try {
      final response = await http.get(Uri.parse(effectiveUrl), headers: headers);
      if (response.statusCode != 200) {
        throw Exception('網路請求失敗，狀態碼: ${response.statusCode}');
      }

      final rawHtml = utf8.decode(response.bodyBytes, allowMalformed: true);
      final parsedContent = parseHtmlContent(rawHtml, effectiveUrl);

      // 若正文實質文字足夠，寫入本地快取
      if (parsedContent.trim().length >= 80) {
        await saveChapterToDb(
          url: effectiveUrl,
          title: effectiveTitle,
          content: parsedContent,
          chapterIndex: chapterIndex,
          bookId: bookId,
        );
      }

      return ChapterContentResult(
        chapterIndex: chapterIndex,
        title: effectiveTitle,
        content: parsedContent,
        chapterUrl: effectiveUrl,
        mode: ReadingMode.nativeText,
        isFromCache: false,
      );
    } catch (e) {
      debugPrint('[ChapterReaderService] 遠端載入章節異常: $e');
      if (cachedContent != null && cachedContent.isNotEmpty) {
        debugPrint('[ChapterReaderService] 載入失敗但有舊快取，降級使用本地快取');
        return ChapterContentResult(
          chapterIndex: chapterIndex,
          title: effectiveTitle,
          content: cachedContent,
          chapterUrl: effectiveUrl,
          mode: ReadingMode.nativeText,
          isFromCache: true,
        );
      }
      rethrow;
    }
  }

  /// 依來源網站解析內文
  String parseHtmlContent(String html, String url) {
    if (url.contains('czbooks.net')) {
      return _parseCzbooks(html);
    } else if (url.contains('po18')) {
      return _parsePo18(html);
    }
    return _cleanGeneralHtml(html);
  }

  String _parseCzbooks(String html) {
    final contentRegex = RegExp(
      r'<div[^>]*class=["\x27][^"\x27]*content[^"\x27]*["\x27][^>]*>([\s\S]*?)<\/div>',
      caseSensitive: false,
    );
    final match = contentRegex.firstMatch(html);
    if (match != null && match.groupCount >= 1) {
      return _cleanGeneralHtml(match.group(1)!);
    }
    return _cleanGeneralHtml(html);
  }

  String _parsePo18(String html) {
    final contentRegex = RegExp(
      r'<div[^>]*class=["\x27][^"\x27]*c_c[^"\x27]*["\x27][^>]*>([\s\S]*?)<\/div>',
      caseSensitive: false,
    );
    final match = contentRegex.firstMatch(html);
    if (match != null && match.groupCount >= 1) {
      return _cleanGeneralHtml(match.group(1)!);
    }
    return _cleanGeneralHtml(html);
  }

  String _cleanGeneralHtml(String html) {
    var text = html.replaceAll(
      RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'<br\s*[\/]?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<\/p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return text.trim();
  }
}