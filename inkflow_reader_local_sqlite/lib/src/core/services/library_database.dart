import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/library/book.dart';
import '../../features/reader/domain/reader_models.dart';

class LibraryDatabase {
  static final LibraryDatabase instance = LibraryDatabase._internal();
  LibraryDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'inkflow_reader.db');
    debugPrint('[DB] 正在初始化資料庫: $path');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDb,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDb(Database db, int version) async {
    debugPrint('[DB] 建立全新資料庫 Schema (v$version)...');
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        sourceType TEXT NOT NULL,
        localPath TEXT,
        textEncoding TEXT,
        fileSize INTEGER,
        catalogUrl TEXT,
        coverPath TEXT,
        latestChapterTitle TEXT,
        catalogSelector TEXT,
        readSelector TEXT,
        createdAt TEXT NOT NULL,
        isFinished INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_states (
        bookId TEXT PRIMARY KEY,
        characterOffset INTEGER NOT NULL DEFAULT 0,
        currentChapterIndex INTEGER NOT NULL DEFAULT 0,
        currentChapter TEXT NOT NULL DEFAULT '',
        progressRatio REAL NOT NULL DEFAULT 0,
        lastReadAt TEXT,
        FOREIGN KEY (bookId) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId TEXT NOT NULL,
        chapterIndex INTEGER NOT NULL,
        title TEXT NOT NULL,
        characterOffset INTEGER NOT NULL DEFAULT 0,
        chapterUrl TEXT,
        isSaved INTEGER NOT NULL DEFAULT 0,
        content TEXT,
        cachedAt TEXT,
        FOREIGN KEY (bookId) REFERENCES books (id) ON DELETE CASCADE,
        UNIQUE (bookId, chapterIndex)
      )
    ''');

    await db.execute('CREATE INDEX idx_chapters_book_pos ON chapters (bookId, chapterIndex)');
    await db.execute('CREATE INDEX idx_chapters_saved ON chapters (bookId, isSaved)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[DB] 升級資料庫：v$oldVersion -> v$newVersion');
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE books ADD COLUMN latestChapterTitle TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN catalogSelector TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN readSelector TEXT');

      await db.execute('ALTER TABLE reading_states ADD COLUMN currentChapterIndex INTEGER NOT NULL DEFAULT 0');

      await db.execute('ALTER TABLE chapters ADD COLUMN chapterUrl TEXT');
      await db.execute('ALTER TABLE chapters ADD COLUMN isSaved INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE chapters ADD COLUMN content TEXT');
      await db.execute('ALTER TABLE chapters ADD COLUMN cachedAt TEXT');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_chapters_book_pos ON chapters (bookId, chapterIndex)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_chapters_saved ON chapters (bookId, isSaved)');
    }
  }

  // =========================================================================
  // 本地書籍與進度 CRUD（已使用白名單過濾，絕不產生 characterOffset 報錯）
  // =========================================================================

  Future<List<Book>> loadBooks() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT b.*,
        COALESCE(r.characterOffset, 0) AS characterOffset,
        COALESCE(r.currentChapter, '') AS currentChapter,
        COALESCE(r.progressRatio, 0) AS progressRatio,
        r.lastReadAt
      FROM books b
      LEFT JOIN reading_states r ON b.id = r.bookId
      ORDER BY b.createdAt DESC
    ''');
    debugPrint('[DB] 載入書架書籍成功，共 ${results.length} 本');
    return results.map((row) => Book.fromMap(row)).toList();
  }

  Future<void> insertBook(Book book, [List<ChapterMarker> chapters = const []]) async {
    final db = await database;
    debugPrint('[DB] 正在寫入書籍: 《${book.title}》(ID: ${book.id})，章節數: ${chapters.length}');

    await db.transaction((txn) async {
      // 關鍵白名單：嚴格只寫入 books 表擁有的欄位
      final bookDbMap = <String, dynamic>{
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'sourceType': book.sourceType.name,
        'localPath': book.localPath,
        'textEncoding': book.textEncoding,
        'fileSize': book.fileSize,
        'catalogUrl': book.catalogUrl,
        'coverPath': book.coverPath,
        'createdAt': book.createdAt is DateTime
            ? (book.createdAt as DateTime).toIso8601String()
            : book.createdAt.toString(),
        'isFinished': book.isFinished ? 1 : 0,
      };

      await txn.insert(
        'books',
        bookDbMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // reading_states 表
      await txn.insert(
        'reading_states',
        {
          'bookId': book.id,
          'characterOffset': book.characterOffset,
          'currentChapter': book.currentChapter,
          'progressRatio': book.progressRatio,
          'lastReadAt': book.lastReadAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (chapters.isNotEmpty) {
        await _replaceChapters(txn, book.id, chapters);
      }
    });
    debugPrint('[DB] 書籍《${book.title}》與章節寫入完成！');
  }

  Future<void> updateBook(Book book) async {
    final db = await database;
    final updateMap = <String, dynamic>{
      'title': book.title,
      'author': book.author,
      'isFinished': book.isFinished ? 1 : 0,
      if (book.coverPath != null) 'coverPath': book.coverPath,
    };
    await db.update(
      'books',
      updateMap,
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<void> saveProgress(Book book) async {
    final db = await database;
    await db.insert(
      'reading_states',
      {
        'bookId': book.id,
        'characterOffset': book.characterOffset,
        'currentChapter': book.currentChapter,
        'progressRatio': book.progressRatio.clamp(0, 1),
        'lastReadAt': (book.lastReadAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChapterMarker>> loadChapters(String bookId) async {
    final db = await database;
    final list = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterIndex ASC',
    );
    return [
      for (final row in list)
        ChapterMarker(
          row['title']! as String,
          row['characterOffset']! as int,
        ),
    ];
  }

  Future<void> replaceChapters(String bookId, List<ChapterMarker> chapters) async {
    final db = await database;
    await db.transaction((txn) => _replaceChapters(txn, bookId, chapters));
  }

  Future<void> _replaceChapters(
    DatabaseExecutor db,
    String bookId,
    List<ChapterMarker> chapters,
  ) async {
    await db.delete('chapters', where: 'bookId = ?', whereArgs: [bookId]);
    final batch = db.batch();
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      batch.insert('chapters', {
        'bookId': bookId,
        'chapterIndex': i,
        'title': ch.title,
        'characterOffset': ch.offset,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteBook(String bookId) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
    debugPrint('[DB] 已刪除書籍 ID: $bookId');
  }

  // =========================================================================
  // 線上小說優化 API
  // =========================================================================

  Future<void> insertOrUpdateCatalog(String bookId, List<Map<String, dynamic>> chapterList) async {
    final db = await database;
    debugPrint('[DB] 正在批次寫入/更新線上章節目錄: 共 ${chapterList.length} 章');
    final batch = db.batch();

    for (final item in chapterList) {
      batch.insert(
        'chapters',
        {
          'bookId': bookId,
          'chapterIndex': item['chapterIndex'],
          'title': item['title'],
          'characterOffset': item['characterOffset'] ?? 0,
          'chapterUrl': item['chapterUrl'],
          'isSaved': item['isSaved'] ?? 0,
          'content': item['content'],
          'cachedAt': item['cachedAt'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('[DB] 線上章節目錄寫入完畢！');
  }

  Future<void> saveChapterContent(String bookId, int chapterIndex, String content) async {
    final db = await database;
    await db.update(
      'chapters',
      {
        'content': content,
        'isSaved': 1,
        'cachedAt': DateTime.now().toIso8601String(),
      },
      where: 'bookId = ? AND chapterIndex = ?',
      whereArgs: [bookId, chapterIndex],
    );
    debugPrint('[DB] 已快取章節 $chapterIndex 內文 (字數: ${content.length})');
  }

  Future<Map<String, dynamic>?> getChapter(String bookId, int chapterIndex) async {
    final db = await database;
    final list = await db.query(
      'chapters',
      where: 'bookId = ? AND chapterIndex = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<Map<String, dynamic>>> getUncachedChapters(String bookId) async {
    final db = await database;
    return await db.query(
      'chapters',
      where: 'bookId = ? AND isSaved = 0',
      whereArgs: [bookId],
      orderBy: 'chapterIndex ASC',
    );
  }
}