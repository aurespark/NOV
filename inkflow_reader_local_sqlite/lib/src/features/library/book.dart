enum BookSourceType { local, web }

enum BookSort { lastRead, title, progress }

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.sourceType,
    required this.characterOffset,
    required this.currentChapter,
    required this.progressRatio,
    required this.createdAt,
    required this.isFinished,
    this.localPath,
    this.textEncoding,
    this.fileSize,
    this.catalogUrl,
    this.catalogSelector,
    this.coverPath,
    this.lastReadAt,
  });

  final String id;
  final String title;
  final String author;
  final BookSourceType sourceType;
  final String? localPath;
  final String? textEncoding;
  final int? fileSize;
  final String? catalogUrl;
  final String? catalogSelector;
  final String? coverPath;
  final int characterOffset;
  final String currentChapter;
  final double progressRatio;
  final DateTime? lastReadAt;
  final DateTime createdAt;
  final bool isFinished;

  Book copyWith({
    String? title,
    String? author,
    String? localPath,
    String? textEncoding,
    int? fileSize,
    String? catalogUrl,
    String? catalogSelector,
    String? coverPath,
    int? characterOffset,
    String? currentChapter,
    double? progressRatio,
    DateTime? lastReadAt,
    bool? isFinished,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    sourceType: sourceType,
    localPath: localPath ?? this.localPath,
    textEncoding: textEncoding ?? this.textEncoding,
    fileSize: fileSize ?? this.fileSize,
    catalogUrl: catalogUrl ?? this.catalogUrl,
    catalogSelector: catalogSelector ?? this.catalogSelector,
    coverPath: coverPath ?? this.coverPath,
    characterOffset: characterOffset ?? this.characterOffset,
    currentChapter: currentChapter ?? this.currentChapter,
    progressRatio: progressRatio ?? this.progressRatio,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    createdAt: createdAt,
    isFinished: isFinished ?? this.isFinished,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'author': author,
    'sourceType': sourceType.name,
    'localPath': localPath,
    'textEncoding': textEncoding,
    'fileSize': fileSize,
    'catalogUrl': catalogUrl,
    'catalogSelector': catalogSelector,
    'coverPath': coverPath,
    'characterOffset': characterOffset,
    'currentChapter': currentChapter,
    'progressRatio': progressRatio.clamp(0, 1),
    'lastReadAt': lastReadAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'isFinished': isFinished ? 1 : 0,
  };

  factory Book.fromMap(Map<String, Object?> map) => Book(
    id: map['id']! as String,
    title: map['title']! as String,
    author: map['author']! as String,
    sourceType: BookSourceType.values.byName(map['sourceType']! as String),
    localPath: map['localPath'] as String?,
    textEncoding: map['textEncoding'] as String?,
    fileSize: map['fileSize'] as int?,
    catalogUrl: map['catalogUrl'] as String?,
    catalogSelector: map['catalogSelector'] as String?,
    coverPath: map['coverPath'] as String?,
    characterOffset: map['characterOffset']! as int,
    currentChapter: map['currentChapter']! as String,
    progressRatio: (map['progressRatio']! as num).toDouble(),
    lastReadAt: map['lastReadAt'] == null
        ? null
        : DateTime.parse(map['lastReadAt']! as String),
    createdAt: DateTime.parse(map['createdAt']! as String),
    isFinished: map['isFinished'] == 1,
  );
}
