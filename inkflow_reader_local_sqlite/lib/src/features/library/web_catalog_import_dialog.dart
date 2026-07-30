import 'package:flutter/material.dart';

Future<String?> showWebCatalogUrlDialog(BuildContext context) {
  var typedUrl = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('匯入線上小說'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '小說目錄網址',
              hintText: 'https://example.com/catalog',
            ),
            onChanged: (value) => typedUrl = value,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          const SizedBox(height: 12),
          const Text('僅匯入你有權存取的公開或已授權內容；不會繞過登入、驗證或付費限制。'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, typedUrl),
          child: const Text('分析目錄'),
        ),
      ],
    ),
  );
}
