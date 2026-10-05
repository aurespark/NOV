import 'package:flutter/material.dart';
import '../../../core/crawler/crawler_state.dart';

class CrawlerErrorDialog extends StatelessWidget {
  final CrawlerError error;
  final void Function(String url)? onSwitchToWeb;
  final VoidCallback? onRetry;

  const CrawlerErrorDialog({
    super.key,
    required this.error,
    this.onSwitchToWeb,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('線上爬取中斷'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.message, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('錯誤類型: ${error.type.name}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (error.failedUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('出錯網址:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              SelectableText(
                error.failedUrl,
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry?.call();
            },
            child: const Text('重試'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
        if (onSwitchToWeb != null && error.failedUrl.isNotEmpty)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onSwitchToWeb?.call(error.failedUrl);
            },
            child: const Text('切換至網頁閱讀'),
          ),
      ],
    );
  }
}
