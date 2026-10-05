import 'package:flutter/foundation.dart';

class AppLogger {
  static const String prefix = '[INKFLOW]';

  static void click(String title, String id, String url) {
    _output('$prefix[CLICK] 點擊書卡: 《$title》 | ID: $id | 原始網址: $url');
  }

  static void step(String stepName, [Map<String, dynamic>? details]) {
    final detailStr = details != null && details.isNotEmpty ? ' -> $details' : '';
    _output('$prefix[STEP] $stepName$detailStr');
  }

  static void crawler(String message) {
    _output('$prefix[CRAWLER] $message');
  }

  static void reader(String message) {
    _output('$prefix[READER] $message');
  }

  static void db(String message) {
    _output('$prefix[DATABASE] $message');
  }

  static void error(String message, [dynamic error, StackTrace? stack]) {
    _output('$prefix[ERROR] $message ${error != null ? "--> $error" : ""}');
    if (stack != null) {
      _output('$prefix[STACK] $stack');
    }
  }

  static void _output(String text) {
    // 同時使用 print 與 debugPrint，確保不受日誌節流限制
    print(text);
    if (kDebugMode) {
      debugPrint(text);
    }
  }
}
