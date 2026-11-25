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
  // Blank edges are drawn as blank space in the expanded template, and a
  // trailing newline is the most common one: a body that ended with one used
  // to leave an empty line between the words and the buttons.
  text = nexNotificationBody(text) ?? '';
  if (text.isEmpty) return '';
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

DefaultStyleInformation nexNotificationStyle(String? body) {
  final text = nexNotificationBody(body);
  return text == null
      ? const DefaultStyleInformation(true, true)
      : BigTextStyleInformation(
          nexAndroidNotificationText(text),
          htmlFormatBigText: true,
          htmlFormatContent: true,
          htmlFormatTitle: true,
        );
}

/// The title and body as the shade should receive them.
///
/// Trimmed, with no blank lines at either end, runs of blank lines folded to
/// one, and — the case a reminder actually hit — a body that only repeats the
/// title dropped. Android draws both, one under the other, so a module or a
/// reminder that passed the same sentence twice read as a bug. An empty body
/// is no body at all: a second, empty line under a title is worse than none.
({String title, String? body}) nexNotificationWords(
  String title,
  String? body,
) {
  final cleanTitle = title.trim();
  final text = nexNotificationBody(body);
  if (text == null || text == cleanTitle) {
    return (title: cleanTitle, body: null);
  }
  return (title: cleanTitle, body: text);
}

/// [text] without blank edges or doubled blank lines, or null when nothing is
/// left. The one place both the words and the style clean up, so a body can
/// never be trimmed for the title and untrimmed for its expanded copy.
String? nexNotificationBody(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final lines = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      // Never at the start, never twice in a row.
      if (lines.isEmpty || lines.last.isEmpty) continue;
      lines.add('');
      continue;
    }
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  // Edges only: indentation inside the body is the words' own.
  final joined = lines.join('\n').trim();
  return joined.isEmpty ? null : joined;
}
