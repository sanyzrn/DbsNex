import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, TextDirection;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' show Bidi;

import 'package:nex_ui/nex_ui.dart' show nexDirectionOf;

/// System notification templates align to the phone's language by default.
/// Android's supported HTML paragraph alignment overrides that with the text's
/// own direction, in both the collapsed and expanded system templates.
String? nexNotificationText(String? text) => Platform.isAndroid && text != null
    ? nexAndroidNotificationText(text)
    : text;

/// [phone] is the direction the phone's own language reads in, which is
/// how Android aligns a notification by default; it is read from the system
/// when not given.
String nexAndroidNotificationText(String text, {TextDirection? phone}) {
  if (text.isEmpty) return text;
  const escape = HtmlEscape();
  final directions = <TextDirection?>[];
  final lines = text.split('\n').map((line) {
    final direction = nexDirectionOf(line);
    directions.add(direction);
    final mark = switch (direction) {
      TextDirection.rtl => '\u200f',
      TextDirection.ltr => '\u200e',
      null => '',
    };
    return '$mark${escape.convert(line)}';
  }).toList();
  final joined = lines.join('<br>');
  final system =
      phone ??
      (Bidi.isRtlLanguage(PlatformDispatcher.instance.locale.languageCode)
          ? TextDirection.rtl
          : TextDirection.ltr);
  // Text that already reads the phone's way needs no alignment of its own,
  // and the alignment costs something: Android ends a <div> with two line
  // breaks, which the expanded notification drew as blank lines under the
  // text. Only text that reads against the phone gets the paragraph.
  if (directions.every((d) => d == null || d == system)) return joined;
  // ALIGN_NORMAL follows each paragraph's first strong character. Merely
  // adding RLM without this leaves Android's viewStart alignment unchanged.
  return '<div style="text-align:start;">$joined</div>';
}

DefaultStyleInformation nexNotificationStyle(String? body) =>
    body == null || body.isEmpty
    ? const DefaultStyleInformation(true, true)
    : BigTextStyleInformation(
        nexAndroidNotificationText(body),
        htmlFormatBigText: true,
        htmlFormatContent: true,
        htmlFormatTitle: true,
      );
