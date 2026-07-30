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
    this.backgroundColor = const Color(0xff000000),
    this.textColor = const Color(0xfff2f2f2),
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
