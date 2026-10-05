class ChapterCacheEntry {
  final int? id;
  final String bookId;
  final int chapterIndex;
  final String title;
  final String content;
  final String sourceUrl;
  final int updatedAt;
  final bool isMerged;

  ChapterCacheEntry({
    this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    required this.content,
    required this.sourceUrl,
    required this.updatedAt,
    this.isMerged = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'title': title,
      'content': content,
      'source_url': sourceUrl,
      'updated_at': updatedAt,
      'is_merged': isMerged ? 1 : 0,
    };
  }

  factory ChapterCacheEntry.fromMap(Map<String, dynamic> map) {
    return ChapterCacheEntry(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      chapterIndex: map['chapter_index'] as int,
      title: map['title'] as String,
      content: map['content'] as String,
      sourceUrl: map['source_url'] as String? ?? '',
      updatedAt: map['updated_at'] as int,
      isMerged: (map['is_merged'] as int? ?? 0) == 1,
    );
  }

  ChapterCacheEntry copyWith({
    int? id,
    String? bookId,
    int? chapterIndex,
    String? title,
    String? content,
    String? sourceUrl,
    int? updatedAt,
    bool? isMerged,
  }) {
    return ChapterCacheEntry(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      title: title ?? this.title,
      content: content ?? this.content,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      updatedAt: updatedAt ?? this.updatedAt,
      isMerged: isMerged ?? this.isMerged,
    );
  }
}
