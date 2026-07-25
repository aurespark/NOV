import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_controller.dart';
import 'package:inkflow_reader/src/features/reader/presentation/reader_settings_sheet.dart';

class TestReaderSettingsController extends ReaderSettingsController {
  @override
  ReaderSettings build() => const ReaderSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(320, 640), Size(800, 900)]) {
    testWidgets('reader settings fit ${size.width.toInt()}px width', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerSettingsProvider.overrideWith(
              TestReaderSettingsController.new,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderSettingsSheet(
                chapters: const [
                  ChapterMarker('第一章 很長很長的章節名稱', 0),
                  ChapterMarker('第二章', 100),
                ],
                currentOffset: 0,
                onChapterSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('章節'), findsWidgets);
      expect(find.text('閱讀設定'), findsWidgets);

      if (size.width < 600) {
        await tester.tap(find.text('閱讀設定').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('字體大小'), findsOneWidget);
      }
    });
  }
}
