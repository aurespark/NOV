import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LoadedFont {
  const LoadedFont(this.family, this.path, this.name);
  final String family;
  final String path;
  final String name;
}

class FontLoaderService {
  Future<LoadedFont> importAndLoad(String sourcePath) async {
    if (p.extension(sourcePath).toLowerCase() != '.ttf') {
      throw const FormatException('只能匯入 TTF 字體');
    }
    final bytes = await File(sourcePath).readAsBytes();
    final name = p.basename(sourcePath);
    final family =
        'UserFont_${sha1.convert(bytes).toString().substring(0, 10)}';
    final fontDir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'fonts'),
    );
    await fontDir.create(recursive: true);
    final target = File(p.join(fontDir.path, '$family.ttf'));
    if (!await target.exists()) await target.writeAsBytes(bytes, flush: true);
    await _load(family, bytes);
    return LoadedFont(family, target.path, name);
  }

  Future<void> restore(String family, String path) async {
    final file = File(path);
    if (await file.exists()) await _load(family, await file.readAsBytes());
  }

  Future<void> _load(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
