import 'package:flutter/material.dart';

class FallbackWebViewModal extends StatelessWidget {
  final String initialUrl;
  final Widget? webViewWidget;

  const FallbackWebViewModal({
    super.key,
    required this.initialUrl,
    this.webViewWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          initialUrl,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: webViewWidget ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.public, size: 48, color: Colors.blueGrey),
                  const SizedBox(height: 12),
                  const Text('原始網頁導航'),
                  const SizedBox(height: 8),
                  SelectableText(
                    initialUrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
