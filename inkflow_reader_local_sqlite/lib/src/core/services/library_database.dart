import 'dart:async';
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

    return await openDatabase(
      path,
      version: 2, // v2 版本
      onCreate: _createDb,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDb(Database db, int version) async {
    // 1. books 表
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

    // 2. reading_states 表
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

    // 3. chapters 表
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
  // 原始書架與閱讀進度 CRUD 方法 (恢復原有系統運作)
  // =========================================================================

  /// 載入所有書籍與閱讀進度
  Future<List<Book>> loadBooks() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT b.*, r.characterOffset, r.currentChapter, r.progressRatio, r.lastReadAt
      FROM books b
      LEFT JOIN reading_states r ON b.id = r.bookId
      ORDER BY b.createdAt DESC
    ''');
    return results.map((row) => Book.fromMap(row)).toList();
  }

  /// 新增書籍（含章節清單）
  Future<void> insertBook(Book book, [List<ChapterMarker> chapters = const []]) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'books',
        book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
        final batch = txn.batch();
        for (int i = 0; i < chapters.length; i++) {
          final ch = chapters[i];
          batch.insert(
            'chapters',
            {
              'bookId': book.id,
              'chapterIndex': i,
              'title': ch.title,
              'characterOffset': ch.offset,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  /// 載入本地書籍章節（ChapterMarker）
  Future<List<ChapterMarker>> loadChapters(String bookId) async {
    final db = await database;
    final list = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterIndex ASC',
    );
    return list
        .map((row) => ChapterMarker(
              row['title'] as String,
              row['characterOffset'] as int? ?? 0,
            ))
        .toList();
  }

  /// 替換/重建章節清單
  Future<void> replaceChapters(String bookId, List<ChapterMarker> chapters) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('chapters', where: 'bookId = ?', whereArgs: [bookId]);
      final batch = txn.batch();
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        batch.insert('chapters', {
          'bookId': bookId,
          'chapterIndex': i,
          'title': ch.title,
          'characterOffset': ch.offset,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// 更新書籍基本資料
  Future<void> updateBook(Book book) async {
    final db = await database;
    await db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  /// 儲存/更新閱讀進度
  Future<void> saveProgress(Book book) async {
    final db = await database;
    await db.insert(
      'reading_states',
      {
        'bookId': book.id,
        'characterOffset': book.characterOffset,
        'currentChapter': book.currentChapter,
        'progressRatio': book.progressRatio,
        'lastReadAt': (book.lastReadAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 刪除書籍（CASCADE 會自動刪除對應的 reading_states 與 chapters）
  Future<void> deleteBook(String bookId) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  // =========================================================================
  // 線上小說優化方法 (階段一～階段四新增)
  // =========================================================================

  /// 批次寫入或更新線上目錄
  Future<void> insertOrUpdateCatalog(String bookId, List<Map<String, dynamic>> chapterList) async {
    final db = await database;
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
  }

  /// 儲存單一章節快取內文
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
  }

  /// 取得指定章節快取
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

  /// 取得未快取章節列表
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