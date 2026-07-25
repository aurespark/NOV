import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:charset_converter/charset_converter.dart';
import '../../features/reader/domain/reader_models.dart';

class DecodedText {
  const DecodedText(this.text, this.encoding, this.confident);
  final String text;
  final TextEncoding encoding;
  final bool confident;
}

class EncodingService {
  Future<DecodedText> decode(
    Uint8List bytes, [
    TextEncoding requested = TextEncoding.auto,
  ]) async {
    final detected = requested == TextEncoding.auto
        ? _detect(bytes)
        : requested;
    if (detected == TextEncoding.big5 || detected == TextEncoding.gbk) {
      final name = detected == TextEncoding.big5 ? 'big5' : 'gbk';
      final value = await CharsetConverter.decode(name, bytes);
      return DecodedText(
        _normalize(value),
        detected,
        requested != TextEncoding.auto,
      );
    }
    final result = await Isolate.run(() => _decodeNative(bytes, detected));
    return DecodedText(_normalize(result), detected, true);
  }

  TextEncoding _detect(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) {
      return TextEncoding.utf8;
    }
    if (b.length >= 2 && b[0] == 0xff && b[1] == 0xfe) {
      return TextEncoding.utf16le;
    }
    if (b.length >= 2 && b[0] == 0xfe && b[1] == 0xff) {
      return TextEncoding.utf16be;
    }
    final sample = b.take(200).toList();
    final evenZeros = [
      for (var i = 0; i < sample.length; i += 2)
        if (sample[i] == 0) 1,
    ].length;
    final oddZeros = [
      for (var i = 1; i < sample.length; i += 2)
        if (sample[i] == 0) 1,
    ].length;
    if (oddZeros > sample.length ~/ 6) return TextEncoding.utf16le;
    if (evenZeros > sample.length ~/ 6) return TextEncoding.utf16be;
    try {
      utf8.decode(b, allowMalformed: false);
      return TextEncoding.utf8;
    } catch (_) {
      // Big5 is the safer default for traditional-Chinese libraries.
      return TextEncoding.big5;
    }
  }
}

String _decodeNative(Uint8List bytes, TextEncoding encoding) {
  if (encoding == TextEncoding.utf8) {
    return utf8.decode(bytes, allowMalformed: true).replaceFirst('\ufeff', '');
  }
  final littleEndian = encoding == TextEncoding.utf16le;
  final start =
      bytes.length >= 2 &&
          ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
              (bytes[0] == 0xfe && bytes[1] == 0xff))
      ? 2
      : 0;
  final codes = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    codes.add(
      littleEndian
          ? bytes[i] | bytes[i + 1] << 8
          : bytes[i] << 8 | bytes[i + 1],
    );
  }
  return String.fromCharCodes(codes);
}

String _normalize(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\u0000', '');
