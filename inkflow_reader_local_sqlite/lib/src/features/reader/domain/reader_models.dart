import 'package:flutter/material.dart';

enum TextEncoding { auto, utf8, utf16le, utf16be, big5, gbk }

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
}