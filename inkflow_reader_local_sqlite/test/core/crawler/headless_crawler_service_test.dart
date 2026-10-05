import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/site_rule.dart';
import '../../../lib/src/core/crawler/crawler_state.dart';
import '../../../lib/src/core/crawler/web_crawler_driver.dart';
import '../../../lib/src/core/crawler/headless_crawler_service.dart';

class MockWebCrawlerDriver implements WebCrawlerDriver {
  String? currentUrl;
  Map<String, dynamic> jsResponses = {};
  bool throwTimeoutOnNext = false;

  @override
  Future<void> loadUrl(String url) async {
    currentUrl = url;
  }

  @override
  Future<dynamic> evaluateJavascript(String script) async {
    if (throwTimeoutOnNext) {
      throw TimeoutException('Simulated timeout');
    }

    for (final entry in jsResponses.entries) {
      if (script.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<String?> getCurrentUrl() async => currentUrl;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('HeadlessCrawlerService Tests', () {
    late MockWebCrawlerDriver mockDriver;
    late HeadlessCrawlerService crawlerService;
    final rule = SiteRule.defaultRule();

    setUp(() {
      mockDriver = MockWebCrawlerDriver();
      crawlerService = HeadlessCrawlerService(driver: mockDriver);
    });

    test('開始閱讀模擬點擊與首頁擷取測試', () async {
      mockDriver.jsResponses = {
        'cf-chl-bypass': false,
        '開始閱讀': true,
        rule.contentSelector: {
          'url': 'https://novel.test/book/1/1.html',
          'title': '第一章 抵達邊境',
          'content': '正文第一段內容。',
          'hasNext': true,
          'isNextChapter': false,
        },
      };

      final result = await crawlerService.startReadingFromBookHome(
        bookHomeUrl: 'https://novel.test/book/1',
        rule: rule,
      );

      expect(crawlerService.status, equals(CrawlerStatus.success));
      expect(result.title, equals('第一章 抵達邊境'));
      expect(result.rawContent, equals('正文第一段內容。'));
      expect(result.url, equals('https://novel.test/book/1/1.html'));
    });

    test('模擬點擊下一頁與正文擷取測試', () async {
      mockDriver.currentUrl = 'https://novel.test/book/1/1.html';
      mockDriver.jsResponses = {
        'cf-chl-bypass': false,
        'nextEl.click()': true,
        rule.contentSelector: {
          'url': 'https://novel.test/book/1/2.html',
          'title': '第一章 抵達邊境 (2)',
          'content': '這是同一章的接續段落。',
          'hasNext': true,
          'isNextChapter': false,
        },
      };

      final result = await crawlerService.navigateToNextPage(rule: rule);

      expect(crawlerService.status, equals(CrawlerStatus.success));
      expect(result.url, equals('https://novel.test/book/1/2.html'));
      expect(result.rawContent, contains('接續段落'));
    });

    test('異常中斷測試：找不到下一頁按鈕時停止並記錄失敗網址', () async {
      mockDriver.currentUrl = 'https://novel.test/book/1/final.html';
      mockDriver.jsResponses = {
        'cf-chl-bypass': false,
        'nextEl.click()': false,
      };

      expect(
        () => crawlerService.navigateToNextPage(rule: rule),
        throwsA(isA<CrawlerError>()),
      );

      try {
        await crawlerService.navigateToNextPage(rule: rule);
      } catch (e) {
        expect(crawlerService.status, equals(CrawlerStatus.stoppedOnError));
        expect(crawlerService.lastError, isNotNull);
        expect(crawlerService.lastError!.failedUrl, equals('https://novel.test/book/1/final.html'));
        expect(crawlerService.lastError!.type, equals(CrawlerErrorType.elementNotFound));
      }
    });

    test('異常中斷測試：頁面觸發防爬驗證碼時中斷', () async {
      mockDriver.jsResponses = {
        'cf-chl-bypass': true,
      };

      try {
        await crawlerService.startReadingFromBookHome(
          bookHomeUrl: 'https://novel.test/captcha',
          rule: rule,
        );
        fail('應拋出 CrawlerError');
      } catch (e) {
        expect(crawlerService.status, equals(CrawlerStatus.stoppedOnError));
        expect(crawlerService.lastError!.type, equals(CrawlerErrorType.captchaDetected));
        expect(crawlerService.lastError!.failedUrl, equals('https://novel.test/captcha'));
      }
    });
  });
}
