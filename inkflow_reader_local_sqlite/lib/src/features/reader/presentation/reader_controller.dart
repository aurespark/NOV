import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/font_loader_service.dart';
import '../../reader/domain/reader_models.dart';

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsController, ReaderSettings>(
      ReaderSettingsController.new,
    );

class ReaderSettingsController extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() {
    _restore();
    return const ReaderSettings();
  }

  Future<void> _restore() async {
    final p = SharedPreferencesAsync();
    final fontFamily = await p.getString('fontFamily');
    final fontPath = await p.getString('fontPath');
    if (fontFamily != null && fontPath != null) {
      try {
        await FontLoaderService().restore(fontFamily, fontPath);
      } catch (_) {
        // Keep the default font if a previously imported file is unavailable.
      }
    }
    state = state.copyWith(
      fontFamily: fontFamily,
      fontPath: fontPath,
      fontName: await p.getString('fontName'),
      fontSize: await p.getDouble('fontSize') ?? 21,
      lineHeight: await p.getDouble('lineHeight') ?? 1.75,
      letterSpacing: await p.getDouble('letterSpacing') ?? .4,
      tapPageTurnEnabled: await p.getBool('tapTurn') ?? true,
    );
  }

  Future<void> update(ReaderSettings value) async {
    state = value;
    final p = SharedPreferencesAsync();
    await Future.wait([
      p.setDouble('fontSize', value.fontSize),
      p.setDouble('lineHeight', value.lineHeight),
      p.setDouble('letterSpacing', value.letterSpacing),
      p.setBool('tapTurn', value.tapPageTurnEnabled),
      if (value.fontFamily != null)
        p.setString('fontFamily', value.fontFamily!),
      if (value.fontPath != null) p.setString('fontPath', value.fontPath!),
      if (value.fontName != null) p.setString('fontName', value.fontName!),
    ]);
  }
}

final bookTextProvider = NotifierProvider<BookTextController, String>(
  BookTextController.new,
);

class BookTextController extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final bookTitleProvider = NotifierProvider<BookTitleController, String>(
  BookTitleController.new,
);

class BookTitleController extends Notifier<String> {
  @override
  String build() => '未命名小說';
  void set(String value) => state = value;
}
