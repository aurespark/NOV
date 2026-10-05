import 'dart:async';
import '../models/site_rule.dart';
import 'crawler_state.dart';
import 'web_crawler_driver.dart';

class HeadlessCrawlerService {
  final WebCrawlerDriver driver;
  final Duration timeoutDuration;

  CrawlerStatus _status = CrawlerStatus.idle;
  CrawlerError? _lastError;

  CrawlerStatus get status => _status;
  CrawlerError? get lastError => _lastError;

  HeadlessCrawlerService({
    required this.driver,
    this.timeoutDuration = const Duration(seconds: 15),
  });

  /// 從小說主頁開始：導航至頁面並模擬點擊「開始閱讀」
  Future<ExtractedPageResult> startReadingFromBookHome({
    required String bookHomeUrl,
    required SiteRule rule,
  }) async {
    _status = CrawlerStatus.navigating;
    _lastError = null;

    try {
      await driver.loadUrl(bookHomeUrl).timeout(timeoutDuration);

      // 檢查是否觸發反爬驗證碼
      if (await _detectCaptcha()) {
        throw _recordError(
          bookHomeUrl,
          '偵測到反爬驗證碼或訪問攔截頁面',
          CrawlerErrorType.captchaDetected,
        );
      }

      // 模擬點擊「開始閱讀」
      final clickScript = _buildClickStartReadingScript(rule);
      final dynamic clicked = await driver.evaluateJavascript(clickScript);

      if (clicked != true) {
        throw _recordError(
          bookHomeUrl,
          '找不到「開始閱讀」按鈕或未能成功點擊',
          CrawlerErrorType.elementNotFound,
        );
      }

      // 等待進入第一章正文並提取內容
      return await extractCurrentPage(rule: rule);
    } on TimeoutException {
      throw _recordError(
        bookHomeUrl,
        '載入或點擊「開始閱讀」逾時',
        CrawlerErrorType.timeout,
      );
    } catch (e) {
      if (e is CrawlerError) rethrow;
      throw _recordError(
        bookHomeUrl,
        '未預期的異常: $e',
        CrawlerErrorType.unknown,
      );
    }
  }

  /// 提取當前頁面內容
  Future<ExtractedPageResult> extractCurrentPage({
    required SiteRule rule,
  }) async {
    _status = CrawlerStatus.extracting;
    final currentUrl = await driver.getCurrentUrl() ?? '';

    // 檢查防爬驗證
    if (await _detectCaptcha()) {
      throw _recordError(
        currentUrl,
        '正文頁面偵測到防爬驗證碼',
        CrawlerErrorType.captchaDetected,
      );
    }

    final extractScript = _buildExtractScript(rule);
    final dynamic result = await driver.evaluateJavascript(extractScript);

    if (result == null || result is! Map) {
      throw _recordError(
        currentUrl,
        '無法解析當前頁面正文元素',
        CrawlerErrorType.elementNotFound,
      );
    }

    final pageUrl = (result['url'] as String?) ?? currentUrl;
    final title = (result['title'] as String?) ?? '';
    final content = (result['content'] as String?) ?? '';
    final hasNext = result['hasNext'] == true;
    final isNextChapter = result['isNextChapter'] == true;

    if (content.trim().isEmpty) {
      throw _recordError(
        pageUrl,
        '擷取到的正文內容為空',
        CrawlerErrorType.elementNotFound,
      );
    }

    _status = CrawlerStatus.success;
    return ExtractedPageResult(
      url: pageUrl,
      title: title,
      rawContent: content,
      hasNextPage: hasNext,
      isNextChapter: isNextChapter,
    );
  }

  /// 模擬點擊「下一頁」並等待擷取
  Future<ExtractedPageResult> navigateToNextPage({
    required SiteRule rule,
  }) async {
    _status = CrawlerStatus.navigating;
    final currentUrl = await driver.getCurrentUrl() ?? '';

    try {
      final nextScript = _buildClickNextScript(rule);
      final dynamic clicked = await driver.evaluateJavascript(nextScript);

      if (clicked != true) {
        throw _recordError(
          currentUrl,
          '找不到「下一頁／下一章」按鈕或已達最新章節',
          CrawlerErrorType.elementNotFound,
        );
      }

      // 等待翻頁載入並擷取
      return await extractCurrentPage(rule: rule);
    } on TimeoutException {
      throw _recordError(
        currentUrl,
        '翻至下一頁逾時',
        CrawlerErrorType.timeout,
      );
    } catch (e) {
      if (e is CrawlerError) rethrow;
      throw _recordError(
        currentUrl,
        '翻頁發生異常: $e',
        CrawlerErrorType.unknown,
      );
    }
  }

  CrawlerError _recordError(String url, String message, CrawlerErrorType type) {
    _status = CrawlerStatus.stoppedOnError;
    final error = CrawlerError(failedUrl: url, message: message, type: type);
    _lastError = error;
    return error;
  }

  Future<bool> _detectCaptcha() async {
    const captchaCheckScript = '''
      (function() {
        const text = document.body ? document.body.innerText : '';
        const keywords = ['cf-chl-bypass', 'challenge-platform', '驗證碼', '验证码', '請進行安全驗證', '请进行安全验证'];
        for (let kw of keywords) {
          if (text.includes(kw)) return true;
        }
        return false;
      })();
    ''';
    final dynamic res = await driver.evaluateJavascript(captchaCheckScript);
    return res == true;
  }

  String _buildClickStartReadingScript(SiteRule rule) {
    final selector = rule.startReadSelector ?? 'a';
    return '''
      (function() {
        let el = document.querySelector('$selector');
        if (!el) {
          const allLinks = Array.from(document.querySelectorAll('a, button, div.read'));
          el = allLinks.find(a => /開始閱讀|开始阅读|點擊閱讀|立即閱讀/.test(a.textContent || ''));
        }
        if (el) {
          el.click();
          return true;
        }
        return false;
      })();
    ''';
  }

  String _buildExtractScript(SiteRule rule) {
    return '''
      (function() {
        const titleEl = document.querySelector('${rule.titleSelector ?? "h1"}');
        const contentEl = document.querySelector('${rule.contentSelector}');
        
        const nextEl = document.querySelector('${rule.nextPageSelector}');
        let nextText = '';
        if (nextEl) {
          nextText = nextEl.textContent || '';
        }
        
        return {
          'url': window.location.href,
          'title': titleEl ? titleEl.innerText : '',
          'content': contentEl ? contentEl.innerText : '',
          'hasNext': !!nextEl,
          'isNextChapter': /下一章|新章節/.test(nextText),
        };
      })();
    ''';
  }

  String _buildClickNextScript(SiteRule rule) {
    return '''
      (function() {
        let nextEl = document.querySelector('${rule.nextPageSelector}');
        if (!nextEl) {
          const links = Array.from(document.querySelectorAll('a'));
          nextEl = links.find(a => /下一頁|下一页|下一章/.test(a.textContent || ''));
        }
        if (nextEl) {
          nextEl.click();
          return true;
        }
        return false;
      })();
    ''';
  }
}
