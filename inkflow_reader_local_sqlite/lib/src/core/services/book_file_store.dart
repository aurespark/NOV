import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BookFileStore {
  Future<String> importTxt(String sourcePath, String bookId) async {
    if (p.extension(sourcePath).toLowerCase() != '.txt') {
      throw const FormatException('只能匯入 TXT 檔案');
    }
    final directory = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'books'),
    );
    await directory.create(recursive: true);
    final temporary = File(p.join(directory.path, '$bookId.tmp'));
    final target = File(p.join(directory.path, '$bookId.txt'));
    try {
      await File(sourcePath).openRead().pipe(temporary.openWrite());
      if (await temporary.length() == 0) {
        throw const FormatException('TXT 檔案是空的');
      }
      await temporary.rename(target.path);
      return target.path;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> delete(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
