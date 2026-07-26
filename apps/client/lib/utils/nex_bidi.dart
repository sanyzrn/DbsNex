import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

TextDirection nexTextDirection(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return TextDirection.ltr;
  return Bidi.estimateDirectionOfText(text) == TextDirection.RTL
      ? TextDirection.rtl
      : TextDirection.ltr;
}

TextAlign nexTextAlign(String? value) =>
    nexTextDirection(value) == TextDirection.rtl ? TextAlign.right : TextAlign.left;