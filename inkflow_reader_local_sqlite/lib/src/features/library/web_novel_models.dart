enum WebChapterStatus {
  pending,
  downloading,
  complete,
  partial,
  failed,
  blocked,
}

extension WebChapterStatusTransitions on WebChapterStatus {
  bool canTransitionTo(WebChapterStatus target) => switch (this) {
    WebChapterStatus.pending => target == WebChapterStatus.downloading,
    WebChapterStatus.downloading =>
      target == WebChapterStatus.pending ||
          target == WebChapterStatus.complete ||
          target == WebChapterStatus.partial ||
          target == WebChapterStatus.failed ||
          target == WebChapterStatus.blocked,
    WebChapterStatus.complete ||
    WebChapterStatus.partial ||
    WebChapterStatus.failed ||
    WebChapterStatus.blocked => target == WebChapterStatus.downloading,
  };
}

enum WebPageStatus { pending, complete, failed, blocked }

enum WebDownloadErrorType {
  network,
  timeout,
  http,
  parse,
  blocked,
  storage,
  cancelled,
}

class WebDownloadError {
  const WebDownloadError({
    required this.type,
    required this.message,
    this.httpStatus,
  });

  final WebDownloadErrorType type;
  final String message;
  final int? httpStatus;
}

class WebChapter {
  WebChapter({
    required this.url,
    required this.title,
    required this.position,
    this.id,
    this.bookId,
    this.normalizedUrl,
    this.content,
    this.status = WebChapterStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptAt,
    this.isSourceRemoved = false,
    this.createdAt,
    this.updatedAt,
  }) {
    if ((status == WebChapterStatus.complete ||
            status == WebChapterStatus.partial) &&
        (content == null || content!.trim().isEmpty)) {
      throw ArgumentError.value(
        content,
        'content',
        '${status.name} chapter requires readable content',
      );
    }
  }

  final int? id;
  final String? bookId;
  final String url;
  final String? normalizedUrl;
  final String title;
  final int position;
  final String? content;
  final WebChapterStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final bool isSourceRemoved;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDownloaded => status == WebChapterStatus.complete;

  WebChapter transitionTo(
    WebChapterStatus target, {
    String? content,
    String? lastError,
    DateTime? attemptedAt,
    int? retryCount,
  }) {
    if (!status.canTransitionTo(target)) {
      throw StateError(
        'Invalid web chapter transition: ${status.name} -> ${target.name}',
      );
    }
    if (content != null &&
        target != WebChapterStatus.complete &&
        target != WebChapterStatus.partial) {
      throw ArgumentError.value(
        content,
        'content',
        'Chapter content can only change after a successful or partial result',
      );
    }
    final nextContent = content ?? this.content;
    if ((target == WebChapterStatus.complete ||
            target == WebChapterStatus.partial) &&
        (nextContent == null || nextContent.trim().isEmpty)) {
      throw StateError('${target.name} requires readable chapter content');
    }
    return WebChapter(
      id: id,
      bookId: bookId,
      url: url,
      normalizedUrl: normalizedUrl,
      title: title,
      position: position,
      content: nextContent,
      status: target,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError,
      lastAttemptAt: attemptedAt,
      isSourceRemoved: isSourceRemoved,
      createdAt: createdAt,
      updatedAt: attemptedAt ?? DateTime.now().toUtc(),
    );
  }

  WebChapter copyWith({
    int? id,
    String? bookId,
    String? url,
    String? normalizedUrl,
    String? title,
    int? position,
    String? content,
    WebChapterStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? lastAttemptAt,
    bool? isSourceRemoved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WebChapter(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    url: url ?? this.url,
    normalizedUrl: normalizedUrl ?? this.normalizedUrl,
    title: title ?? this.title,
    position: position ?? this.position,
    content: content ?? this.content,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError ?? this.lastError,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    isSourceRemoved: isSourceRemoved ?? this.isSourceRemoved,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    if (bookId != null) 'bookId': bookId,
    'url': url,
    'normalizedUrl': normalizedUrl ?? url,
    'title': title,
    'position': position,
    'content': content,
    'status': status.name,
    'isDownloaded': isDownloaded ? 1 : 0,
    'retryCount': retryCount,
    'lastError': lastError,
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
    'isSourceRemoved': isSourceRemoved ? 1 : 0,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory WebChapter.fromMap(Map<String, Object?> map) => WebChapter(
    id: map['id'] as int?,
    bookId: map['bookId'] as String?,
    url: map['url']! as String,
    normalizedUrl: map['normalizedUrl'] as String?,
    title: map['title']! as String,
    position: map['position']! as int,
    content: map['content'] as String?,
    status: WebChapterStatus.values.byName(
      (map['status'] as String?) ?? WebChapterStatus.pending.name,
    ),
    retryCount: (map['retryCount'] as int?) ?? 0,
    lastError: map['lastError'] as String?,
    lastAttemptAt: _dateFromMap(map['lastAttemptAt']),
    isSourceRemoved: map['isSourceRemoved'] == 1,
    createdAt: _dateFromMap(map['createdAt']),
    updatedAt: _dateFromMap(map['updatedAt']),
  );
}

class WebChapterPage {
  WebChapterPage({
    required this.chapterId,
    required this.pageIndex,
    required this.sourceUrl,
    this.id,
    this.normalizedUrl,
    this.content,
    this.status = WebPageStatus.pending,
    this.errorReason,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.createdAt,
    this.updatedAt,
  }) {
    if (status == WebPageStatus.complete &&
        (content == null || content!.trim().isEmpty)) {
      throw ArgumentError.value(
        content,
        'content',
        'complete page requires readable content',
      );
    }
  }

  final int? id;
  final int chapterId;
  final int pageIndex;
  final String sourceUrl;
  final String? normalizedUrl;
  final String? content;
  final WebPageStatus status;
  final String? errorReason;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'chapterId': chapterId,
    'pageIndex': pageIndex,
    'sourceUrl': sourceUrl,
    'normalizedUrl': normalizedUrl ?? sourceUrl,
    'content': content,
    'status': status.name,
    'errorReason': errorReason,
    'retryCount': retryCount,
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory WebChapterPage.fromMap(Map<String, Object?> map) => WebChapterPage(
    id: map['id'] as int?,
    chapterId: map['chapterId']! as int,
    pageIndex: map['pageIndex']! as int,
    sourceUrl: map['sourceUrl']! as String,
    normalizedUrl: map['normalizedUrl'] as String?,
    content: map['content'] as String?,
    status: WebPageStatus.values.byName(
      (map['status'] as String?) ?? WebPageStatus.pending.name,
    ),
    errorReason: map['errorReason'] as String?,
    retryCount: (map['retryCount'] as int?) ?? 0,
    lastAttemptAt: _dateFromMap(map['lastAttemptAt']),
    createdAt: _dateFromMap(map['createdAt']),
    updatedAt: _dateFromMap(map['updatedAt']),
  );
}

class WebDownloadResult {
  WebDownloadResult({
    required this.status,
    required this.content,
    this.pages = const [],
    this.error,
  }) {
    const terminal = {
      WebChapterStatus.complete,
      WebChapterStatus.partial,
      WebChapterStatus.failed,
      WebChapterStatus.blocked,
    };
    if (!terminal.contains(status)) {
      throw ArgumentError.value(status, 'status', 'must be terminal');
    }
    if ((status == WebChapterStatus.complete ||
            status == WebChapterStatus.partial) &&
        content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'must be readable');
    }
    if ((status == WebChapterStatus.complete ||
            status == WebChapterStatus.partial) &&
        !pages.any(
          (page) =>
              page.status == WebPageStatus.complete &&
              (page.content?.trim().isNotEmpty ?? false),
        )) {
      throw ArgumentError.value(
        pages,
        'pages',
        'readable result requires at least one complete page',
      );
    }
    if ((status == WebChapterStatus.failed ||
            status == WebChapterStatus.blocked) &&
        content.isNotEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        '${status.name} result cannot replace cached content',
      );
    }
  }

  final WebChapterStatus status;
  final String content;
  final List<WebChapterPage> pages;
  final WebDownloadError? error;
}

enum WebCatalogChangeType { added, updated, sourceRemoved, unchanged }

class WebCatalogChange {
  const WebCatalogChange({
    required this.type,
    this.existingChapterId,
    this.incoming,
    this.confidence = 1,
  });

  final WebCatalogChangeType type;
  final int? existingChapterId;
  final WebChapter? incoming;
  final double confidence;
}

class WebCatalogDiff {
  const WebCatalogDiff({required this.changes});

  final List<WebCatalogChange> changes;

  List<WebCatalogChange> _ofType(WebCatalogChangeType type) =>
      changes.where((change) => change.type == type).toList(growable: false);

  List<WebCatalogChange> get added => _ofType(WebCatalogChangeType.added);
  List<WebCatalogChange> get updated => _ofType(WebCatalogChangeType.updated);
  List<WebCatalogChange> get sourceRemoved =>
      _ofType(WebCatalogChangeType.sourceRemoved);
  List<WebCatalogChange> get unchanged =>
      _ofType(WebCatalogChangeType.unchanged);
}

class WebChapterReadingState {
  const WebChapterReadingState({
    required this.chapterId,
    required this.bookId,
    this.paragraphAnchor,
    this.progressRatio = 0,
    this.isRead = false,
    this.lastReadAt,
  });

  final int chapterId;
  final String bookId;
  final String? paragraphAnchor;
  final double progressRatio;
  final bool isRead;
  final DateTime? lastReadAt;

  Map<String, Object?> toMap() => {
    'chapterId': chapterId,
    'bookId': bookId,
    'paragraphAnchor': paragraphAnchor,
    'progressRatio': progressRatio.clamp(0, 1),
    'isRead': isRead ? 1 : 0,
    'lastReadAt': lastReadAt?.toIso8601String(),
  };

  factory WebChapterReadingState.fromMap(Map<String, Object?> map) =>
      WebChapterReadingState(
        chapterId: map['chapterId']! as int,
        bookId: map['bookId']! as String,
        paragraphAnchor: map['paragraphAnchor'] as String?,
        progressRatio: ((map['progressRatio'] as num?) ?? 0).toDouble(),
        isRead: map['isRead'] == 1,
        lastReadAt: _dateFromMap(map['lastReadAt']),
      );
}

enum WebDownloadJobMode { preview, fullBook }

enum WebDownloadJobStatus { pending, running, paused, complete, failed, cancelled }

class WebDownloadJob {
  const WebDownloadJob({
    required this.bookId,
    required this.mode,
    required this.queuePosition,
    this.id,
    this.status = WebDownloadJobStatus.pending,
    this.completedCount = 0,
    this.partialCount = 0,
    this.failedCount = 0,
    this.blockedCount = 0,
    this.lastError,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String bookId;
  final WebDownloadJobMode mode;
  final int queuePosition;
  final WebDownloadJobStatus status;
  final int completedCount;
  final int partialCount;
  final int failedCount;
  final int blockedCount;
  final String? lastError;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WebDownloadJob copyWith({
    WebDownloadJobStatus? status,
    int? completedCount,
    int? partialCount,
    int? failedCount,
    int? blockedCount,
    String? lastError,
  }) => WebDownloadJob(
    id: id,
    bookId: bookId,
    mode: mode,
    queuePosition: queuePosition,
    status: status ?? this.status,
    completedCount: completedCount ?? this.completedCount,
    partialCount: partialCount ?? this.partialCount,
    failedCount: failedCount ?? this.failedCount,
    blockedCount: blockedCount ?? this.blockedCount,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
  );
}

DateTime? _dateFromMap(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
