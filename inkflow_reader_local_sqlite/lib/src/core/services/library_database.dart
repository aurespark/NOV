import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../features/library/book.dart';
import '../../features/reader/domain/reader_models.dart';

class LibraryDatabase {
  LibraryDatabase._();
  static final instance = LibraryDatabase._();
  Database? _database;

  Future<Database> get database async =>
      _database ??= await openDatabase(
        p.join(await getDatabasesPath(), 'inkflow_reader.db'),
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
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
          await _createWebChaptersTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE books ADD COLUMN catalogSelector TEXT',
            );
          }
          if (oldVersion < 3) {
            await _createWebChaptersTable(db);
          }
        },
      );

  Future<void> _createWebChaptersTable(DatabaseExecutor db) async {
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

  Future<void> insertBook(Book book,
      {List<ChapterMarker>? localChapters,
      List<WebChapter>? webChapters}) async {
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
        ChapterMarker(
          row['title']! as String,
          row['characterOffset']! as int,
        ),
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
    return [
      for (final row in rows)
        WebChapter(
          title: row['title']! as String,
          url: row['url']! as String,
          position: row['position']! as int,
        ),
    ];
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

  Future<void> deleteBook(String bookId) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
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
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.insert('web_chapters', {
        'bookId': bookId,
        'title': chapter.title,
        'url': chapter.url,
        'position': chapter.position,
      });
    }
    await batch.commit(noResult: true);
  }
}
