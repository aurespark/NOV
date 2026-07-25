import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/library/book.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_controller.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_view.dart';

class TestReaderSettingsController extends ReaderSettingsController {
  @override
  ReaderSettings build() => const ReaderSettings(
    fontSize: 30,
    lineHeight: 1.8,
    tapPageTurnEnabled: true,
  );
}

class TestBookTextController extends BookTextController {
  @override
  String build() {
    return List.generate(
      120,
      (index) => '第${index + 1}頁 ${'閱讀內容 ' * 8}',
    ).join('\n');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('left and right taps both advance to the next page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final book = Book(
      id: 'book-1',
      title: '閱讀測試',
      author: '測試作者',
      sourceType: BookSourceType.local,
      localPath: '/books/book-1.txt',
      characterOffset: 0,
      currentChapter: '全文',
      progressRatio: 0,
      createdAt: DateTime.utc(2026, 7, 26),
      isFinished: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readerSettingsProvider.overrideWith(
            TestReaderSettingsController.new,
          ),
          bookTextProvider.overrideWith(TestBookTextController.new),
        ],
        child: MaterialApp(
          home: ReaderView(
            book: book,
            chapters: const [ChapterMarker('全文', 0)],
          ),
        ),
      ),
    );

    await _pumpUntilPageCounterReady(tester);

    final initial = _pageCounterText(tester);
    expect(initial, isNotNull);
    final initialPage = _parseCurrentPage(initial!);
    final totalPages = _parseTotalPages(initial);
    expect(totalPages, greaterThan(2));
    expect(initialPage, 1);

    await tester.tapAt(const Offset(24, 320));
    await tester.pump();

    final afterLeftTap = _pageCounterText(tester);
    expect(afterLeftTap, isNotNull);
    expect(_parseCurrentPage(afterLeftTap!), 2);
    expect(_parseTotalPages(afterLeftTap), totalPages);

    await tester.tapAt(const Offset(336, 320));
    await tester.pump();

    final afterRightTap = _pageCounterText(tester);
    expect(afterRightTap, isNotNull);
    expect(_parseCurrentPage(afterRightTap!), 3);
    expect(_parseTotalPages(afterRightTap), totalPages);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntilPageCounterReady(WidgetTester tester) async {
  for (var i = 0; i < 240; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (_pageCounterText(tester) != null) return;
  }
  fail('timed out waiting for the reader page counter');
}

String? _pageCounterText(WidgetTester tester) {
  final matcher = find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    final data = widget.data?.trim();
    return data != null && RegExp(r'^\d+ / \d+$').hasMatch(data);
  });
  if (matcher.evaluate().isEmpty) return null;
  return tester.widget<Text>(matcher.first).data?.trim();
}

int _parseCurrentPage(String text) {
  return int.parse(text.split(' / ').first);
}

int _parseTotalPages(String text) {
  return int.parse(text.split(' / ').last);
}
