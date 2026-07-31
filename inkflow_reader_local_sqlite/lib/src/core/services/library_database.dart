import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/library/book.dart';
import '../../features/library/web_novel_models.dart';
import '../../features/reader/domain/reader_models.dart' show ChapterMarker;

class LibraryDatabase {
  LibraryDatabase({DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory,
      _databasePath = databasePath;

  LibraryDatabase._() : _databaseFactory = null, _databasePath = null;

  static const schemaVersion = 4;
  static final instance = LibraryDatabase._();

  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database {
    final opened = _database;
    if (opened != null) return Future.value(opened);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    try {
      final path =
          _databasePath ??
          p.join(await getDatabasesPath(), 'inkflow_reader.db');
      final options = OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        onDowngrade: (_, oldVersion, newVersion) {
          throw StateError(
            'Database downgrade is not supported: $oldVersion -> $newVersion',
          );
        },
      );
      final opened = _databaseFactory == null
          ? await openDatabase(
              path,
              version: options.version,
              onConfigure: options.onConfigure,
              onCreate: options.onCreate,
              onUpgrade: options.onUpgrade,
              onDowngrade: options.onDowngrade,
            )
          : await _databaseFactory.openDatabase(path, options: options);
      try {
        await _repairInterruptedDownloads(opened);
      } catch (_) {
        await opened.close();
        rethrow;
      }
      _database = opened;
      return opened;
    } finally {
      _opening = null;
    }
  }

  Future<void> close() async {
    final opened = _database;
    _database = null;
    _opening = null;
    await opened?.close();
  }

  Future<void> _createSchema(Database db, int _) async {
    await db.execute('''
      CREATE TABLE books(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        sourceType TEXT NOT NULL,
        localPath TEXT,
        textEncoding TEXT,
        fileSize INTEGER,
        catalogUrl TEXT,
        catalogSelector TEXT,
        coverPath TEXT,
        createdAt TEXT NOT NULL,
        isFinished INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE reading_states(
        bookId TEXT PRIMARY KEY,
        characterOffset INTEGER NOT NULL DEFAULT 0,
        currentChapter TEXT NOT NULL DEFAULT '',
        progressRatio REAL NOT NULL DEFAULT 0,
        lastReadAt TEXT,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId TEXT NOT NULL,
        chapterIndex INTEGER NOT NULL,
        title TEXT NOT NULL,
        characterOffset INTEGER NOT NULL,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE(bookId, chapterIndex)
      )
    ''');
    await _createWebChaptersV4(db);
    await _createWebV4Tables(db);
    await _createWebV4Indexes(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE books ADD COLUMN catalogSelector TEXT');
    }
    if (oldVersion < 3) {
      await _createWebChaptersV3(db);
    }
    if (oldVersion < 4 && newVersion >= 4) {
      // sqflite runs onUpgrade inside one transaction. A failure in any of
      // these statements therefore rolls the entire v4 migration back.
      await _upgradeWebChaptersToV4(db);
      await _createWebV4Tables(db);
      await _createWebV4Indexes(db);
    }
  }

  Future<void> _createWebChaptersV3(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE web_chapters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        position INTEGER NOT NULL,
        isDownloaded INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE(bookId, url)
      )
    ''');
  }

  Future<void> _createWebChaptersV4(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE web_chapters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId TEXT NOT NULL,
        url TEXT NOT NULL,
        normalizedUrl TEXT NOT NULL,
        title TEXT NOT NULL,
        position INTEGER NOT NULL,
        content TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        isDownloaded INTEGER NOT NULL DEFAULT 0,
        retryCount INTEGER NOT NULL DEFAULT 0,
        lastError TEXT,
        lastAttemptAt TEXT,
        isSourceRemoved INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE(bookId, url)
      )
    ''');
  }

  Future<void> _upgradeWebChaptersToV4(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE web_chapters ADD COLUMN normalizedUrl TEXT');
    await db.execute('ALTER TABLE web_chapters ADD COLUMN content TEXT');
    await db.execute(
      "ALTER TABLE web_chapters ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
    );
    await db.execute(
      'ALTER TABLE web_chapters ADD COLUMN retryCount INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('ALTER TABLE web_chapters ADD COLUMN lastError TEXT');
    await db.execute('ALTER TABLE web_chapters ADD COLUMN lastAttemptAt TEXT');
    await db.execute(
      'ALTER TABLE web_chapters ADD COLUMN isSourceRemoved INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('ALTER TABLE web_chapters ADD COLUMN createdAt TEXT');
    await db.execute('ALTER TABLE web_chapters ADD COLUMN updatedAt TEXT');
    await db.execute('''
      UPDATE web_chapters
      SET normalizedUrl = url,
          status = CASE
            WHEN isDownloaded = 1
              AND LENGTH(TRIM(COALESCE(content, ''))) > 0 THEN 'complete'
            ELSE 'pending'
          END,
          isDownloaded = CASE
            WHEN isDownloaded = 1
              AND LENGTH(TRIM(COALESCE(content, ''))) > 0 THEN 1
            ELSE 0
          END,
          createdAt = COALESCE(createdAt, CURRENT_TIMESTAMP),
          updatedAt = COALESCE(updatedAt, CURRENT_TIMESTAMP)
    ''');
  }

  Future<void> _createWebV4Tables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE web_chapter_pages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapterId INTEGER NOT NULL,
        pageIndex INTEGER NOT NULL,
        sourceUrl TEXT NOT NULL,
        normalizedUrl TEXT NOT NULL,
        content TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        errorReason TEXT,
        retryCount INTEGER NOT NULL DEFAULT 0,
        lastAttemptAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY(chapterId) REFERENCES web_chapters(id) ON DELETE CASCADE,
        UNIQUE(chapterId, pageIndex)
      )
    ''');
    await db.execute('''
      CREATE TABLE web_chapter_reading_states(
        chapterId INTEGER PRIMARY KEY,
        bookId TEXT NOT NULL,
        paragraphAnchor TEXT,
        progressRatio REAL NOT NULL DEFAULT 0,
        isRead INTEGER NOT NULL DEFAULT 0,
        lastReadAt TEXT,
        FOREIGN KEY(chapterId) REFERENCES web_chapters(id) ON DELETE CASCADE,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE web_download_jobs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId TEXT NOT NULL UNIQUE,
        mode TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        queuePosition INTEGER NOT NULL,
        completedCount INTEGER NOT NULL DEFAULT 0,
        partialCount INTEGER NOT NULL DEFAULT 0,
        failedCount INTEGER NOT NULL DEFAULT 0,
        blockedCount INTEGER NOT NULL DEFAULT 0,
        lastError TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createWebV4Indexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX idx_web_chapters_book_normalized_url
      ON web_chapters(bookId, normalizedUrl)
    ''');
    await db.execute('''
      CREATE INDEX idx_web_chapter_pages_chapter_status
      ON web_chapter_pages(chapterId, status)
    ''');
    await db.execute('''
      CREATE INDEX idx_web_download_jobs_queue
      ON web_download_jobs(status, queuePosition)
    ''');
  }

  Future<List<Book>> loadBooks() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT b.*,
        COALESCE(r.characterOffset, 0) AS characterOffset,
        COALESCE(r.currentChapter, '') AS currentChapter,
        COALESCE(r.progressRatio, 0) AS progressRatio,
        r.lastReadAt
      FROM books b
      LEFT JOIN reading_states r ON r.bookId = b.id
    ''');
    return rows.map(Book.fromMap).toList();
  }

  Future<void> insertBook(
    Book book, {
    List<ChapterMarker>? localChapters,
    List<WebChapter>? webChapters,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final map = book.toMap()
        ..remove('characterOffset')
        ..remove('currentChapter')
        ..remove('progressRatio')
        ..remove('lastReadAt');
      await transaction.insert('books', map);
      await transaction.insert('reading_states', {
        'bookId': book.id,
        'characterOffset': book.characterOffset,
        'currentChapter': book.currentChapter,
        'progressRatio': book.progressRatio,
        'lastReadAt': book.lastReadAt?.toIso8601String(),
      });
      if (localChapters != null) {
        await _replaceChapters(transaction, book.id, localChapters);
      }
      if (webChapters != null) {
        await _replaceWebChapters(transaction, book.id, webChapters);
      }
    });
  }

  Future<void> updateBook(Book book) async {
    final db = await database;
    final map = book.toMap()
      ..remove('characterOffset')
      ..remove('currentChapter')
      ..remove('progressRatio')
      ..remove('lastReadAt')
      ..remove('createdAt')
      ..remove('sourceType')
      ..remove('localPath')
      ..remove('textEncoding')
      ..remove('fileSize')
      ..remove('catalogUrl');
    await db.update('books', map, where: 'id = ?', whereArgs: [book.id]);
  }

  Future<void> saveProgress(Book book) async {
    final db = await database;
    await db.insert('reading_states', {
      'bookId': book.id,
      'characterOffset': book.characterOffset,
      'currentChapter': book.currentChapter,
      'progressRatio': book.progressRatio.clamp(0, 1),
      'lastReadAt': book.lastReadAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChapterMarker>> loadChapters(String bookId) async {
    final db = await database;
    final rows = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterIndex',
    );
    return [
      for (final row in rows)
        ChapterMarker(row['title']! as String, row['characterOffset']! as int),
    ];
  }

  Future<List<WebChapter>> loadWebChapters(String bookId) async {
    final db = await database;
    final rows = await db.query(
      'web_chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'position',
    );
    return rows.map(WebChapter.fromMap).toList(growable: false);
  }

  Future<WebChapter?> loadWebChapter(int chapterId) async {
    final db = await database;
    final rows = await db.query(
      'web_chapters',
      where: 'id = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    return rows.isEmpty ? null : WebChapter.fromMap(rows.single);
  }

  Future<void> replaceChapters(
    String bookId,
    List<ChapterMarker> chapters,
  ) async {
    final db = await database;
    await db.transaction(
      (transaction) => _replaceChapters(transaction, bookId, chapters),
    );
  }

  Future<void> replaceWebChapters(
    String bookId,
    List<WebChapter> chapters,
  ) async {
    final db = await database;
    await db.transaction(
      (transaction) => _replaceWebChapters(transaction, bookId, chapters),
    );
  }

  Future<void> updateWebChapterStatus(
    int chapterId,
    WebChapterStatus status, {
    String? content,
    String? lastError,
    DateTime? attemptedAt,
    bool incrementRetryCount = false,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final chapter = await _loadWebChapter(transaction, chapterId);
      if (chapter == null) {
        throw StateError('Web chapter $chapterId does not exist');
      }
      final transitioned = chapter.transitionTo(
        status,
        content: content,
        lastError: lastError,
        attemptedAt: attemptedAt,
        retryCount: incrementRetryCount ? chapter.retryCount + 1 : null,
      );
      await transaction.update(
        'web_chapters',
        _downloadStateMap(transitioned),
        where: 'id = ?',
        whereArgs: [chapterId],
      );
    });
  }

  Future<void> finishWebChapterDownload(
    int chapterId,
    WebDownloadResult result,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      final chapter = await _loadWebChapter(transaction, chapterId);
      if (chapter == null) {
        throw StateError('Web chapter $chapterId does not exist');
      }
      final now = DateTime.now().toUtc();
      for (final page in result.pages) {
        if (page.chapterId != chapterId) {
          throw StateError(
            'Page ${page.pageIndex} belongs to chapter ${page.chapterId}',
          );
        }
        await transaction.insert(
          'web_chapter_pages',
          _webChapterPageMap(page, now.toIso8601String()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final transitioned = chapter.transitionTo(
        result.status,
        content:
            result.status == WebChapterStatus.complete ||
                result.status == WebChapterStatus.partial
            ? result.content
            : null,
        lastError: result.error?.message,
        attemptedAt: now,
      );
      await transaction.update(
        'web_chapters',
        _downloadStateMap(transitioned),
        where: 'id = ?',
        whereArgs: [chapterId],
      );
    });
  }

  Future<void> upsertWebChapterPage(WebChapterPage page) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'web_chapter_pages',
      _webChapterPageMap(page, now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<WebChapterPage>> loadWebChapterPages(int chapterId) async {
    final db = await database;
    final rows = await db.query(
      'web_chapter_pages',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
      orderBy: 'pageIndex',
    );
    return rows.map(WebChapterPage.fromMap).toList(growable: false);
  }

  Future<void> saveWebChapterReadingState(WebChapterReadingState state) async {
    final db = await database;
    await db.insert(
      'web_chapter_reading_states',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<WebChapterReadingState?> loadWebChapterReadingState(
    int chapterId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'web_chapter_reading_states',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    return rows.isEmpty ? null : WebChapterReadingState.fromMap(rows.single);
  }

  Future<void> saveWebDownloadJob(WebDownloadJob job) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('web_download_jobs', {
      if (job.id != null) 'id': job.id,
      'bookId': job.bookId,
      'mode': job.mode.name,
      'status': job.status.name,
      'queuePosition': job.queuePosition,
      'completedCount': job.completedCount,
      'partialCount': job.partialCount,
      'failedCount': job.failedCount,
      'blockedCount': job.blockedCount,
      'lastError': job.lastError,
      'createdAt': job.createdAt?.toIso8601String() ?? now,
      'updatedAt': job.updatedAt?.toIso8601String() ?? now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WebDownloadJob>> loadWebDownloadJobs() async {
    final db = await database;
    final rows = await db.query(
      'web_download_jobs',
      orderBy: 'queuePosition, id',
    );
    return [
      for (final row in rows)
        WebDownloadJob(
          id: row['id']! as int,
          bookId: row['bookId']! as String,
          mode: WebDownloadJobMode.values.byName(row['mode']! as String),
          status: WebDownloadJobStatus.values.byName(row['status']! as String),
          queuePosition: row['queuePosition']! as int,
          completedCount: row['completedCount']! as int,
          partialCount: row['partialCount']! as int,
          failedCount: row['failedCount']! as int,
          blockedCount: row['blockedCount']! as int,
          lastError: row['lastError'] as String?,
          createdAt: _parseDate(row['createdAt']),
          updatedAt: _parseDate(row['updatedAt']),
        ),
    ];
  }

  Future<void> deleteWebDownloadJob(String bookId) async {
    final db = await database;
    await db.delete('web_download_jobs', where: 'bookId = ?', whereArgs: [bookId]);
  }

  Future<WebBookSummary> webBookSummary(String bookId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total,
        SUM(CASE WHEN status = 'complete' THEN 1 ELSE 0 END) AS complete,
        SUM(CASE WHEN status = 'partial' THEN 1 ELSE 0 END) AS partial,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
        SUM(CASE WHEN status = 'blocked' THEN 1 ELSE 0 END) AS blocked,
        SUM(LENGTH(COALESCE(content, ''))) AS characters
      FROM web_chapters WHERE bookId = ?
    ''', [bookId]);
    int value(String key) => (rows.single[key] as int?) ?? 0;
    return WebBookSummary(
      total: value('total'), complete: value('complete'), partial: value('partial'),
      failed: value('failed'), blocked: value('blocked'), characters: value('characters'),
    );
  }

  Future<void> clearIncompleteWebCache(String bookId) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query('web_chapters', columns: ['id'],
          where: "bookId = ? AND status IN ('partial','failed')", whereArgs: [bookId]);
      for (final row in rows) {
        await transaction.delete('web_chapter_pages', where: 'chapterId = ?', whereArgs: [row['id']]);
      }
      await transaction.update('web_chapters', {
        'content': null, 'status': WebChapterStatus.pending.name, 'isDownloaded': 0,
        'lastError': null, 'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }, where: "bookId = ? AND status IN ('partial','failed')", whereArgs: [bookId]);
    });
  }

  Future<void> applyWebCatalogDiff(String bookId, WebCatalogDiff diff) async {
    final db = await database;
    await db.transaction((transaction) async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final change in diff.changes) {
        switch (change.type) {
          case WebCatalogChangeType.added:
            final incoming = change.incoming;
            if (incoming == null) {
              throw StateError('Added catalog change requires a chapter');
            }
            await transaction.insert(
              'web_chapters',
              _webChapterInsertMap(bookId, incoming, now),
            );
            break;
          case WebCatalogChangeType.updated:
            final incoming = change.incoming;
            final existingId = change.existingChapterId;
            if (incoming == null || existingId == null) {
              throw StateError(
                'Updated catalog change requires both chapter versions',
              );
            }
            await transaction.update(
              'web_chapters',
              {
                'url': incoming.url,
                'normalizedUrl': incoming.normalizedUrl ?? incoming.url,
                'title': incoming.title,
                'position': incoming.position,
                'isSourceRemoved': 0,
                'updatedAt': now,
              },
              where: 'id = ? AND bookId = ?',
              whereArgs: [existingId, bookId],
            );
            break;
          case WebCatalogChangeType.sourceRemoved:
            final existingId = change.existingChapterId;
            if (existingId == null) {
              throw StateError(
                'Removed catalog change requires an existing chapter',
              );
            }
            await transaction.update(
              'web_chapters',
              {'isSourceRemoved': 1, 'updatedAt': now},
              where: 'id = ? AND bookId = ?',
              whereArgs: [existingId, bookId],
            );
            break;
          case WebCatalogChangeType.unchanged:
            break;
        }
      }
    });
  }

  Future<void> clearWebBookDownloads(String bookId) async {
    final db = await database;
    await db.transaction((transaction) async {
      final chapterRows = await transaction.query(
        'web_chapters',
        columns: ['id'],
        where: 'bookId = ?',
        whereArgs: [bookId],
      );
      for (final row in chapterRows) {
        await transaction.delete(
          'web_chapter_pages',
          where: 'chapterId = ?',
          whereArgs: [row['id']],
        );
      }
      await transaction.update(
        'web_chapters',
        {
          'content': null,
          'status': WebChapterStatus.pending.name,
          'isDownloaded': 0,
          'retryCount': 0,
          'lastError': null,
          'lastAttemptAt': null,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'bookId = ?',
        whereArgs: [bookId],
      );
    });
  }

  Future<void> repairInterruptedDownloads() async {
    await _repairInterruptedDownloads(await database);
  }

  Future<void> deleteBook(String bookId) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'web_download_jobs',
        where: 'bookId = ?',
        whereArgs: [bookId],
      );
      await transaction.delete('books', where: 'id = ?', whereArgs: [bookId]);
    });
  }

  Future<void> _repairInterruptedDownloads(DatabaseExecutor db) async {
    await db.update(
      'web_chapters',
      {
        'status': WebChapterStatus.pending.name,
        'isDownloaded': 0,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'status = ?',
      whereArgs: [WebChapterStatus.downloading.name],
    );
  }

  Future<void> _replaceChapters(
    DatabaseExecutor db,
    String bookId,
    List<ChapterMarker> chapters,
  ) async {
    await db.delete('chapters', where: 'bookId = ?', whereArgs: [bookId]);
    final batch = db.batch();
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      batch.insert('chapters', {
        'bookId': bookId,
        'chapterIndex': index,
        'title': chapter.title,
        'characterOffset': chapter.offset,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _replaceWebChapters(
    DatabaseExecutor db,
    String bookId,
    List<WebChapter> chapters,
  ) async {
    await db.delete('web_chapters', where: 'bookId = ?', whereArgs: [bookId]);
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.insert('web_chapters', _webChapterInsertMap(bookId, chapter, now));
    }
    await batch.commit(noResult: true);
  }

  Map<String, Object?> _webChapterInsertMap(
    String bookId,
    WebChapter chapter,
    String now,
  ) => {
    'bookId': bookId,
    'url': chapter.url,
    'normalizedUrl': chapter.normalizedUrl ?? chapter.url,
    'title': chapter.title,
    'position': chapter.position,
    'content': chapter.content,
    'status': chapter.status.name,
    'isDownloaded': chapter.isDownloaded ? 1 : 0,
    'retryCount': chapter.retryCount,
    'lastError': chapter.lastError,
    'lastAttemptAt': chapter.lastAttemptAt?.toIso8601String(),
    'isSourceRemoved': chapter.isSourceRemoved ? 1 : 0,
    'createdAt': chapter.createdAt?.toIso8601String() ?? now,
    'updatedAt': chapter.updatedAt?.toIso8601String() ?? now,
  };

  Map<String, Object?> _webChapterPageMap(WebChapterPage page, String now) =>
      page.toMap()
        ..remove('id')
        ..['createdAt'] = page.createdAt?.toIso8601String() ?? now
        ..['updatedAt'] = page.updatedAt?.toIso8601String() ?? now;

  Future<WebChapter?> _loadWebChapter(
    DatabaseExecutor db,
    int chapterId,
  ) async {
    final rows = await db.query(
      'web_chapters',
      where: 'id = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    return rows.isEmpty ? null : WebChapter.fromMap(rows.single);
  }

  Map<String, Object?> _downloadStateMap(WebChapter chapter) => {
    'content': chapter.content,
    'status': chapter.status.name,
    'isDownloaded': chapter.isDownloaded ? 1 : 0,
    'retryCount': chapter.retryCount,
    'lastError': chapter.lastError,
    'lastAttemptAt': chapter.lastAttemptAt?.toIso8601String(),
    'updatedAt':
        chapter.updatedAt?.toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
  };
}

class WebBookSummary {
  const WebBookSummary({required this.total, required this.complete, required this.partial,
    required this.failed, required this.blocked, required this.characters});
  final int total;
  final int complete;
  final int partial;
  final int failed;
  final int blocked;
  final int characters;
  double get downloadRatio => total == 0 ? 0 : complete / total;
  int get approximateBytes => characters * 2;
}

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
