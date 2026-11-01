import 'dart:convert';
import 'dart:io';
import 'dart:ui' show TextDirection;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:nex_ui/nex_ui.dart' show nexDirectionOf;

/// System notification templates align to the phone's language by default.
/// Android's supported HTML paragraph alignment overrides that with the text's
/// own direction, in both the collapsed and expanded system templates.
String? nexNotificationText(String? text) => Platform.isAndroid && text != null
    ? nexAndroidNotificationText(text)
    : text;

String nexAndroidNotificationText(String text) {
  if (text.isEmpty) return text;
  const escape = HtmlEscape();
  final lines = text.split('\n').map((line) {
    final mark = switch (nexDirectionOf(line)) {
      TextDirection.rtl => '\u200f',
      TextDirection.ltr => '\u200e',
      null => '',
    };
    return '$mark${escape.convert(line)}';
  });
  // ALIGN_NORMAL follows each paragraph's first strong character. Merely
  // adding RLM without this leaves Android's viewStart alignment unchanged.
  return '<div style="text-align:start;">${lines.join('<br>')}</div>';
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
