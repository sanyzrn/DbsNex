import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

TextDirection nexTextDirection(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return TextDirection.ltr;
  return intl.Bidi.estimateDirectionOfText(text) == intl.TextDirection.RTL
      ? TextDirection.rtl
      : TextDirection.ltr;
}

TextAlign nexTextAlign(String? value) =>
    nexTextDirection(value) == TextDirection.rtl
    ? TextAlign.right
    : TextAlign.left;
