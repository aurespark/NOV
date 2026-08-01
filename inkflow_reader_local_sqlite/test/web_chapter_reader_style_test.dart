import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/library/web_chapter_reader_view.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';

void main() {
  testWidgets('線上章節標題與正文共用全域 TTF 閱讀設定', (tester) async {
    const settings = ReaderSettings(
      fontFamily: 'UserFont_test',
      fontSize: 23,
      lineHeight: 1.6,
      letterSpacing: .7,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebChapterBody(
            title: '第一章',
            content: '正文內容',
            settings: settings,
            isPartial: false,
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('web-chapter-title')),
    );
    final content = tester.widget<Text>(
      find.byKey(const ValueKey('web-chapter-content')),
    );

    expect(title.style?.fontFamily, 'UserFont_test');
    expect(content.style?.fontFamily, 'UserFont_test');
    expect(content.style?.fontSize, 23);
    expect(content.style?.height, 1.6);
    expect(content.style?.letterSpacing, .7);
  });
}
