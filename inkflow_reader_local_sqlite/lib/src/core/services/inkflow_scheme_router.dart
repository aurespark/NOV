/// 導航動作列舉
enum SchemeActionType {
  openCatalog,
  openChapter,
  nextChapter,
  prevChapter,
}

/// 抽象導航動作基底
abstract class InkflowNavigationAction {
  final SchemeActionType type;
  const InkflowNavigationAction(this.type);
}

/// 開啟目錄頁面動作
class OpenCatalogAction extends InkflowNavigationAction {
  final String bookId;
  final String? catalogUrl;

  const OpenCatalogAction({
    required this.bookId,
    this.catalogUrl,
  }) : super(SchemeActionType.openCatalog);
}

/// 開啟指定章節閱讀動作
class OpenChapterAction extends InkflowNavigationAction {
  final String bookId;
  final int chapterIndex;
  final String? chapterUrl;

  const OpenChapterAction({
    required this.bookId,
    required this.chapterIndex,
    this.chapterUrl,
  }) : super(SchemeActionType.openChapter);
}

/// 切換至下一章動作
class NextChapterAction extends InkflowNavigationAction {
  final String bookId;
  final int? currentChapterIndex;

  const NextChapterAction({
    required this.bookId,
    this.currentChapterIndex,
  }) : super(SchemeActionType.nextChapter);
}

/// 切換至上一章動作
class PrevChapterAction extends InkflowNavigationAction {
  final String bookId;
  final int? currentChapterIndex;

  const PrevChapterAction({
    required this.bookId,
    this.currentChapterIndex,
  }) : super(SchemeActionType.prevChapter);
}

/// 自訂協定解析與路由管理器
class InkflowSchemeRouter {
  static const String scheme = 'inkflow';

  /// 判斷網址是否為內部自訂協定
  static bool isInternalScheme(String rawUrl) {
    final lower = rawUrl.trim().toLowerCase();
    return lower.startsWith('$scheme:') ||
        lower.startsWith('catalog:') ||
        lower.startsWith('read:');
  }

  /// 解析 URL 為強型別動作
  static InkflowNavigationAction? parse(String rawUrl) {
    if (!isInternalScheme(rawUrl)) return null;

    final trimmed = rawUrl.trim();

    // 1. 標準 inkflow:// 協定解析
    if (trimmed.toLowerCase().startsWith('$scheme://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;

      final host = uri.host.toLowerCase();
      final params = uri.queryParameters;
      final bookId = params['bookId'] ?? '';

      switch (host) {
        case 'catalog':
          return OpenCatalogAction(
            bookId: bookId,
            catalogUrl: params['catalogUrl'],
          );
        case 'read':
        case 'chapter':
          final index = int.tryParse(params['chapterIndex'] ?? '0') ?? 0;
          return OpenChapterAction(
            bookId: bookId,
            chapterIndex: index,
            chapterUrl: params['chapterUrl'],
          );
        case 'next':
          final currentIndex = int.tryParse(params['currentChapterIndex'] ?? '');
          return NextChapterAction(
            bookId: bookId,
            currentChapterIndex: currentIndex,
          );
        case 'prev':
          final currentIndex = int.tryParse(params['currentChapterIndex'] ?? '');
          return PrevChapterAction(
            bookId: bookId,
            currentChapterIndex: currentIndex,
          );
      }
    }

    // 2. 向下相容 APK 特殊協定格式 catalog:...
    if (trimmed.toLowerCase().startsWith('catalog:')) {
      final afterColon = trimmed.substring('catalog:'.length);
      if (afterColon.startsWith('?')) {
        final queryUri = Uri.tryParse('inkflow://catalog$afterColon');
        if (queryUri != null) {
          return OpenCatalogAction(
            bookId: queryUri.queryParameters['bookId'] ?? '',
            catalogUrl: queryUri.queryParameters['catalogUrl'],
          );
        }
      }
      return OpenCatalogAction(bookId: afterColon.trim());
    }

    // 3. 向下相容 APK 特殊協定格式 read:...
    if (trimmed.toLowerCase().startsWith('read:')) {
      final afterColon = trimmed.substring('read:'.length);
      if (afterColon.startsWith('?')) {
        final queryUri = Uri.tryParse('inkflow://read$afterColon');
        if (queryUri != null) {
          final index = int.tryParse(queryUri.queryParameters['chapterIndex'] ?? '0') ?? 0;
          return OpenChapterAction(
            bookId: queryUri.queryParameters['bookId'] ?? '',
            chapterIndex: index,
            chapterUrl: queryUri.queryParameters['chapterUrl'],
          );
        }
      }

      final parts = afterColon.split('/');
      final bookId = parts.isNotEmpty ? parts[0] : '';
      final index = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      return OpenChapterAction(bookId: bookId, chapterIndex: index);
    }

    return null;
  }

  /// 產生標準閱讀章節 URI
  static String buildReadUri({
    required String bookId,
    required int chapterIndex,
    String? chapterUrl,
  }) {
    final query = <String, String>{
      'bookId': bookId,
      'chapterIndex': chapterIndex.toString(),
      if (chapterUrl != null) 'chapterUrl': chapterUrl,
    };
    return Uri(
      scheme: scheme,
      host: 'read',
      queryParameters: query,
    ).toString();
  }

  /// 產生標準目錄 URI
  static String buildCatalogUri({
    required String bookId,
    String? catalogUrl,
  }) {
    final query = <String, String>{
      'bookId': bookId,
      if (catalogUrl != null) 'catalogUrl': catalogUrl,
    };
    return Uri(
      scheme: scheme,
      host: 'catalog',
      queryParameters: query,
    ).toString();
  }
}