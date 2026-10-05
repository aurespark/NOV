import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/chapter_cache_entry.dart';

class DatabaseService {
  static const String dbName = 'inkflow_novel_reader.db';
  static const int dbVersion = 2;
  static const String tableChapters = 'chapters';

  static const String createTableQuery = '''
    CREATE TABLE $tableChapters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      source_url TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      is_merged INTEGER DEFAULT 0,
      UNIQUE(book_id, chapter_index)
    )
  ''';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, dbName);

    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) async {
        await db.execute(createTableQuery);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $tableChapters ADD COLUMN source_url TEXT DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE $tableChapters ADD COLUMN is_merged INTEGER DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> saveChapter(ChapterCacheEntry entry) async {
    final db = await database;
    await db.insert(
      tableChapters,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChapterCacheEntry?> getChapter(String bookId, int chapterIndex) async {
    final db = await database;
    final results = await db.query(
      tableChapters,
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return ChapterCacheEntry.fromMap(results.first);
  }

  Future<ChapterCacheEntry?> getChapterBySourceUrl(String sourceUrl) async {
    final db = await database;
    final results = await db.query(
      tableChapters,
      where: 'source_url = ?',
      whereArgs: [sourceUrl],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return ChapterCacheEntry.fromMap(results.first);
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
