abstract class WebCrawlerDriver {
  Future<void> loadUrl(String url);
  Future<dynamic> evaluateJavascript(String script);
  Future<String?> getCurrentUrl();
  Future<void> dispose();
}
