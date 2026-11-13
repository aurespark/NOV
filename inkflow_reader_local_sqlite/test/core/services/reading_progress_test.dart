import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/library_database.dart';
import 'package:inkflow_reader/src/features/library/book.dart';
import 'package:sqflite/sqflite.dart';

/// 只模擬 reading_states 單表的 update / insert / query，足以驗證欄位不互相覆蓋。
class _StatesDb extends Fake implements Database {
  final rows = <String, Map<String, Object?>>{};

  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    final row = rows[whereArgs!.first];
    if (row == null) return 0;
    row.addAll(values);
    return 1;
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    rows[values['bookId'] as String] = {'currentChapterIndex': 0, ...values};
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
          String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
      rows.containsKey(whereArgs!.first) ? [rows[whereArgs.first]!] : [];
}

Book _book(double ratio) => Book(
      id: 'b1',
      title: '測試',
      author: '作者',
      sourceType: BookSourceType.web,
      characterOffset: 10,
      currentChapter: '第3章',
      progressRatio: ratio,
      createdAt: DateTime(2026),
      isFinished: false,
    );

void main() {
  final db = _StatesDb();
  final lib = LibraryDatabase.instance..testDatabase = db;

  setUp(db.rows.clear);

  test('沒有紀錄時讀到第 0 章', () async {
    expect(await lib.loadChapterIndex('b1'), 0);
  });

  test('saveProgress 不會把已存的章節索引重設為 0', () async {
    await lib.saveChapterIndex('b1', 2);
    await lib.saveProgress(_book(0.25));
    expect(await lib.loadChapterIndex('b1'), 2);
    expect(db.rows['b1']!['progressRatio'], 0.25);
  });

  test('先 saveProgress 再存章節：兩邊欄位都保留', () async {
    await lib.saveProgress(_book(0.5));
    await lib.saveChapterIndex('b1', 7);
    expect(await lib.loadChapterIndex('b1'), 7);
    expect(db.rows['b1']!['currentChapter'], '第3章');
  });
}
