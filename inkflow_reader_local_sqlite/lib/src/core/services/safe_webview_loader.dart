import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SafeWebViewLoader extends StatefulWidget {
  const SafeWebViewLoader({super.key, required this.uri, required this.onCompleted, this.hidden = true});
  final Uri uri;
  final ValueChanged<String?> onCompleted;
  final bool hidden;

  static Future<String?> load(BuildContext context, Uri uri) async {
    final completer = Completer<String?>();
    late OverlayEntry entry;
    var removed = false;
    void complete(String? html) {
      if (!completer.isCompleted) completer.complete(html);
      if (!removed) { removed = true; entry.remove(); }
    }
    entry = OverlayEntry(builder: (_) => SafeWebViewLoader(
      uri: uri,
      onCompleted: complete,
    ));
    Overlay.of(context).insert(entry);
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () { complete(null); return null; });
  }

  static Future<void> openExternal(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @override State<SafeWebViewLoader> createState() => _SafeWebViewLoaderState();
}

class _SafeWebViewLoaderState extends State<SafeWebViewLoader> {
  late final WebViewController _controller;
  var _clicks = 0;
  var _completed = false;

  bool _isSameOrigin(Uri uri) => uri.scheme == widget.uri.scheme &&
      uri.host == widget.uri.host && uri.port == widget.uri.port;

  void _complete(String? html) {
    if (_completed) return;
    _completed = true;
    widget.onCompleted(html);
  }

  @override void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && _isSameOrigin(uri)
              ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onWebResourceError: (error) { if (error.isForMainFrame ?? true) _complete(null); },
        onPageFinished: (_) => _finish(),
      ))
      ..loadRequest(widget.uri);
  }

  Future<void> _finish() async {
    if (!mounted) return;
    for (; _clicks < 10; _clicks++) {
      final clicked = await _controller.runJavaScriptReturningResult(r'''
        (() => {
          const ok = /^(展開全文|閱讀全文|載入更多|顯示更多)$/i;
          const blocked = /(下一章|登入|廣告|下載|安裝)/i;
          const el = [...document.querySelectorAll('button,a')]
            .find(e => ok.test(e.innerText.trim()) && !blocked.test(e.innerText));
          if (!el) return false; el.click(); return true;
        })()
      ''');
      if (clicked != true && clicked != 'true') break;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    final result = await _controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
    final html = result is String ? result.replaceAll(r'\"', '"').replaceFirst(RegExp(r'^"'), '').replaceFirst(RegExp(r'"$'), '') : null;
    _complete(html);
  }

  @override Widget build(BuildContext context) => Positioned.fill(child: IgnorePointer(
    ignoring: widget.hidden,
    child: Opacity(opacity: widget.hidden ? 0.001 : 1, child: WebViewWidget(controller: _controller)),
  ));
}
