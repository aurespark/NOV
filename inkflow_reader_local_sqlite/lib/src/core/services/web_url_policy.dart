class WebUrlPolicy {
  const WebUrlPolicy({
    this.maxRedirects = 5,
    this.trackingParameters = const {
      'fbclid',
      'gclid',
      'dclid',
      'msclkid',
      'mc_cid',
      'mc_eid',
      'igshid',
    },
  });

  final int maxRedirects;
  final Set<String> trackingParameters;

  Uri parseAndNormalize(String value, {Uri? baseUrl}) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      throw const FormatException('網址格式無效');
    }
    final resolved = parsed.hasScheme
        ? parsed
        : baseUrl == null
            ? parsed
            : baseUrl.resolveUri(parsed);
    return normalize(resolved);
  }

  Uri normalize(Uri uri) {
    validate(uri);
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = _isDefaultPort(scheme, uri.port) ? null : uri.hasPort ? uri.port : null;
    final path = _normalizePath(uri.path);
    final query = _normalizedQuery(uri);

    return Uri(
      scheme: scheme,
      userInfo: uri.userInfo,
      host: host,
      port: port,
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  void validate(Uri uri, {int redirectCount = 0}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FormatException('只允許 http 或 https 網址：${uri.scheme}');
    }
    if (uri.host.isEmpty) {
      throw const FormatException('網址缺少主機名稱');
    }
    if (redirectCount > maxRedirects) {
      throw FormatException('重新導向超過 $maxRedirects 次');
    }
    if (_isPrivateHost(uri.host)) {
      throw const FormatException('不允許存取本機或私人網路位址');
    }
  }

  Map<String, String> _normalizedQuery(Uri uri) {
    final entries = uri.queryParametersAll.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final result = <String, String>{};
    for (final entry in entries) {
      final key = entry.key;
      final lower = key.toLowerCase();
      if (lower.startsWith('utm_') || trackingParameters.contains(lower)) {
        continue;
      }
      final values = [...entry.value]..sort();
      result[key] = values.join(',');
    }
    return result;
  }

  String _normalizePath(String value) {
    final collapsed = value.replaceAll(RegExp(r'/+'), '/');
    final segments = <String>[];
    for (final segment in collapsed.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    final normalized = '/${segments.join('/')}';
    if (normalized.length > 1 && value.endsWith('/')) return '$normalized/';
    return normalized;
  }

  bool _isDefaultPort(String scheme, int port) =>
      (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443);

  bool _isPrivateHost(String rawHost) {
    final host = rawHost.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    final ipv4 = host.split('.');
    if (ipv4.length == 4) {
      final parts = ipv4.map(int.tryParse).toList();
      if (parts.any((part) => part == null || part! < 0 || part > 255)) {
        return false;
      }
      final a = parts[0]!;
      final b = parts[1]!;
      return a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168);
    }
    final compact = host.replaceAll('[', '').replaceAll(']', '');
    return compact == '::1' ||
        compact == '::' ||
        compact.startsWith('fc') ||
        compact.startsWith('fd') ||
        RegExp(r'^fe[89ab]', caseSensitive: false).hasMatch(compact);
  }
}
