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
        version: 1,
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
        },
      );

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

  Future<void> insertBook(Book book, List<ChapterMarker> chapters) async {
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
      await _replaceChapters(transaction, book.id, chapters);
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

  Future<void> replaceChapters(
    String bookId,
    List<ChapterMarker> chapters,
  ) async {
    final db = await database;
    await db.transaction(
      (transaction) => _replaceChapters(transaction, bookId, chapters),
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
}
