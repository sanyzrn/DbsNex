import 'dart:convert';

enum TextCodec { base64, url, hex }

/// Bounded UTF-8 text transformations. These formats provide no secrecy.
class TextConversion {
  static const maxBytes = 8192;
  static String run(String input, TextCodec mode, {required bool decode}) {
    if (input.length > maxBytes ||
        utf8.encode(input).length > maxBytes ||
        utf8.decode(utf8.encode(input)) != input) {
      throw const FormatException('input too large');
    }
    if (!decode) {
      final bytes = utf8.encode(input);
      return switch (mode) {
        TextCodec.base64 => base64Encode(bytes),
        TextCodec.url => Uri.encodeComponent(input),
        TextCodec.hex =>
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
      };
    }
    return switch (mode) {
      TextCodec.base64 => _base64(input),
      TextCodec.url => _url(input),
      TextCodec.hex => _hex(input),
    };
  }

  static String _url(String text) {
    try {
      return Uri.decodeComponent(text);
    } on ArgumentError {
      throw const FormatException('invalid URL component');
    }
  }

  static String _base64(String text) {
    if (text.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(text)) {
      throw const FormatException('invalid base64');
    }
    final bytes = base64Decode(text);
    if (base64Encode(bytes) != text) {
      throw const FormatException('noncanonical base64');
    }
    return utf8.decode(bytes);
  }

  static String _hex(String text) {
    // Whitespace may separate complete bytes, never split a byte or hide junk.
    if (text.isEmpty) return '';
    if (!RegExp(r'^(?:[0-9a-fA-F]{2})+(?:[ \t\r\n]+(?:[0-9a-fA-F]{2})+)*$')
        .hasMatch(text)) {
      throw const FormatException('invalid hex');
    }
    final compact = text.replaceAll(RegExp(r'[ \t\r\n]'), '');
    return utf8.decode([
      for (var i = 0; i < compact.length; i += 2)
        int.parse(compact.substring(i, i + 2), radix: 16),
    ]);
  }
}
