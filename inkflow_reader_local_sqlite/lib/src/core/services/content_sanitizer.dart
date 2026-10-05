class ContentSanitizer {
  static String sanitize(String rawContent, {List<String> customRemovals = const []}) {
    if (rawContent.isEmpty) return '';

    String cleaned = rawContent;

    cleaned = cleaned.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');

    for (final removal in customRemovals) {
      if (removal.isNotEmpty) {
        cleaned = cleaned.replaceAll(removal, '');
      }
    }

    cleaned = cleaned
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");

    final lines = cleaned.split(RegExp(r'\r?\n'));
    final formattedLines = <String>[];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (_isAdLine(trimmed)) continue;

      formattedLines.add('    $trimmed');
    }

    return formattedLines.join('\n\n');
  }

  static bool _isAdLine(String line) {
    final adSignatures = [
      RegExp(r'^(ps|ps:|溫馨提示|温馨提示).*', caseSensitive: false),
      RegExp(r'.*(請記住本站|请记住本站|點擊下一頁|点击下一页).*', caseSensitive: false),
      RegExp(r'.*(無廣告閱讀|无广告阅读|防採集|防采集).*', caseSensitive: false),
    ];

    for (final regex in adSignatures) {
      if (regex.hasMatch(line)) return true;
    }
    return false;
  }
}
