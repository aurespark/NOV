import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/crawler/crawler_state.dart';
import '../../../lib/src/features/reader/widgets/crawler_error_dialog.dart';

void main() {
  testWidgets('CrawlerErrorDialog 顯示錯誤訊息、網址並支援跳轉', (WidgetTester tester) async {
    String? redirectedUrl;
    final error = CrawlerError(
      failedUrl: 'https://novel.test/error_chapter.html',
      message: '模擬觸發防爬驗證碼',
      type: CrawlerErrorType.captchaDetected,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrawlerErrorDialog(
            error: error,
            onSwitchToWeb: (url) {
              redirectedUrl = url;
            },
          ),
        ),
      ),
    );

    expect(find.text('線上爬取中斷'), findsOneWidget);
    expect(find.text('模擬觸發防爬驗證碼'), findsOneWidget);
    expect(find.text('https://novel.test/error_chapter.html'), findsOneWidget);

    // 點擊「切換至網頁閱讀」
    await tester.tap(find.text('切換至網頁閱讀'));
    await tester.pumpAndSettle();

    expect(redirectedUrl, equals('https://novel.test/error_chapter.html'));
  });
}
