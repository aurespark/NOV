import 'package:flutter/material.dart';

enum TextEncoding { auto, utf8, utf16le, utf16be, big5, gbk }

class PageRange {
  const PageRange(this.start, this.end);
  final int start;
  final int end;
}

class ChapterMarker {
  const ChapterMarker(this.title, this.offset);
  final String title;
  final int offset;
}

class ChapterParser {
  static final _heading = RegExp(
    r'^[ \t]*(第[0-9０-９一二三四五六七八九十百千零〇兩两]+[章回卷節部篇][^\r\n]*|(?:chapter|section)[ \t]+[0-9０-９]+[^\r\n]*|序章|楔子|前言|後記)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );

  static List<ChapterMarker> parse(String text) {
    final chapters = _heading
        .allMatches(text)
        .map((match) => ChapterMarker(match.group(1)!.trim(), match.start))
        .toList();
    return chapters.isEmpty ? const [ChapterMarker('全文', 0)] : chapters;
  }
}

@immutable
class ReaderSettings {
  const ReaderSettings({
    this.fontFamily,
    this.fontPath,
    this.fontName,
    this.fontSize = 21,
    this.lineHeight = 1.75,
    this.letterSpacing = .4,
    this.backgroundColor = const Color(0xfff4ecd8),
    this.textColor = const Color(0xff3b332b),
    this.tapPageTurnEnabled = true,
    this.encoding = TextEncoding.auto,
  });

  final String? fontFamily;
  final String? fontPath;
  final String? fontName;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final Color backgroundColor;
  final Color textColor;
  final bool tapPageTurnEnabled;
  final TextEncoding encoding;

  TextStyle get textStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineHeight,
    letterSpacing: letterSpacing,
    color: textColor,
  );

  ReaderSettings copyWith({
    String? fontFamily,
    String? fontPath,
    String? fontName,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    Color? backgroundColor,
    Color? textColor,
    bool? tapPageTurnEnabled,
    TextEncoding? encoding,
  }) => ReaderSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontPath: fontPath ?? this.fontPath,
    fontName: fontName ?? this.fontName,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    textColor: textColor ?? this.textColor,
    tapPageTurnEnabled: tapPageTurnEnabled ?? this.tapPageTurnEnabled,
    encoding: encoding ?? this.encoding,
  );
}
// -------------------------------------------------------------
// 線上小說章節模型 (階段一～階段四優化新增)
// -------------------------------------------------------------
class ChapterItem {
  final int? id;
  final String bookId;
  final int chapterIndex;
  final String title;
  final int characterOffset;
  final String? chapterUrl;
  final bool isSaved;
  final String? content;
  final DateTime? cachedAt;

  ChapterItem({
    this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    this.characterOffset = 0,
    this.chapterUrl,
    this.isSaved = false,
    this.content,
    this.cachedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'title': title,
      'characterOffset': characterOffset,
      'chapterUrl': chapterUrl,
      'isSaved': isSaved ? 1 : 0,
      'content': content,
      'cachedAt': cachedAt?.toIso8601String(),
    };
  }

  factory ChapterItem.fromMap(Map<String, dynamic> map) {
    return ChapterItem(
      id: map['id'] as int?,
      bookId: map['bookId'] as String,
      chapterIndex: map['chapterIndex'] as int,
      title: map['title'] as String,
      characterOffset: map['characterOffset'] as int? ?? 0,
      chapterUrl: map['chapterUrl'] as String?,
      isSaved: (map['isSaved'] as int? ?? 0) == 1,
      content: map['content'] as String?,
      cachedAt: map['cachedAt'] != null ? DateTime.tryParse(map['cachedAt'] as String) : null,
    );
  }

  ChapterItem copyWith({
    int? id,
    String? bookId,
    int? chapterIndex,
    String? title,
    int? characterOffset,
    String? chapterUrl,
    bool? isSaved,
    String? content,
    DateTime? cachedAt,
  }) {
    return ChapterItem(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      title: title ?? this.title,
      characterOffset: characterOffset ?? this.characterOffset,
      chapterUrl: chapterUrl ?? this.chapterUrl,
      isSaved: isSaved ?? this.isSaved,
      content: content ?? this.content,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}