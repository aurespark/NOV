import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/features/library/web_catalog_import_dialog.dart';

void main() {
  testWidgets('catalog URL dialog can repeatedly cancel and submit', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              submitted = await showWebCatalogUrlDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://example.com/book/42',
    );
    await tester.tap(find.text('分析目錄'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(submitted, 'https://example.com/book/42');
  });
}
