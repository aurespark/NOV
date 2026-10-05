enum CrawlerStatus {
  idle,
  navigating,
  extracting,
  success,
  stoppedOnError,
}

enum CrawlerErrorType {
  timeout,
  elementNotFound,
  captchaDetected,
  httpError,
  unknown,
}

class CrawlerError {
  final String failedUrl;
  final String message;
  final CrawlerErrorType type;
  final int timestamp;

  CrawlerError({
    required this.failedUrl,
    required this.message,
    required this.type,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  @override
  String toString() => 'CrawlerError(type: $type, url: $failedUrl, message: $message)';
}

class ExtractedPageResult {
  final String url;
  final String title;
  final String rawContent;
  final bool hasNextPage;
  final bool isNextChapter;

  ExtractedPageResult({
    required this.url,
    required this.title,
    required this.rawContent,
    required this.hasNextPage,
    required this.isNextChapter,
  });
}
