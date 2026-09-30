/// What an assistant reply rests on, taken out of its prose.
///
/// The assistant is asked to end an answer that used the user's notes with a
/// line naming them — `Sources: [id] [id]`, the ids exactly as its context
/// gave them — and to begin one that did not use them with `[general]`. Those
/// markers are for the app, not the reader: this takes them out of the text
/// and hands them back separately, so the answer is shown as prose with the
/// notes it used as tappable chips underneath.
///
/// Ids are only ever taken from brackets and only kept when [known] says the
/// note exists, so a model that invents an id produces no chip rather than a
/// chip that opens nothing.
class NexCitedReply {
  const NexCitedReply({
    required this.text,
    required this.noteIds,
    required this.general,
  });

  /// The reply as the reader should see it.
  final String text;

  /// The notes the reply says it used, in the order it named them, once each.
  final List<String> noteIds;

  /// Whether the reply says it answered from general knowledge rather than
  /// from the user's notes.
  final bool general;

  static const _uuid =
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  /// `[id]`, and the `[id, id]` some models write instead of two brackets.
  static final _bracketed = RegExp(
    r'\[\s*(' + _uuid + r'(?:\s*[,،]\s*' + _uuid + r')*)\s*\]',
  );
  static final _one = RegExp(_uuid);

  /// A line that was only a label once its ids were taken out: "Sources:",
  /// "منابع:", or nothing but punctuation.
  static final _labelOnly = RegExp(
    r'^[\s*_>\-–—•:،,.()]*(sources?|references?|notes? used|منابع|منبع|یادداشت‌های استفاده‌شده)?[\s*_:،,.()]*$',
    caseSensitive: false,
  );

  static final _generalMarker = RegExp(
    r'^\s*\[general\]\s*',
    caseSensitive: false,
  );

  /// Splits [reply] into prose and citations. With [known], an id is kept only
  /// if it is in that set; without it every well-formed id is kept.
  static NexCitedReply parse(String reply, {Set<String>? known}) {
    var text = reply;
    var general = false;
    if (_generalMarker.hasMatch(text)) {
      general = true;
      text = text.replaceFirst(_generalMarker, '');
    }

    final ids = <String>[];
    final lines = <String>[];
    for (final line in text.split('\n')) {
      if (!_bracketed.hasMatch(line)) {
        lines.add(line);
        continue;
      }
      for (final match in _bracketed.allMatches(line)) {
        for (final id in _one.allMatches(match.group(1)!)) {
          final value = id.group(0)!.toLowerCase();
          if (known != null && !known.contains(value)) continue;
          if (!ids.contains(value)) ids.add(value);
        }
      }
      final rest = line
          .replaceAll(_bracketed, '')
          .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
          .replaceAllMapped(
            RegExp(r' +([.,;:!?،؛])'),
            (match) => match.group(1)!,
          );
      if (_labelOnly.hasMatch(rest)) continue;
      lines.add(rest.trimRight());
    }
    return NexCitedReply(
      text: lines.join('\n').trim(),
      noteIds: ids,
      general: general,
    );
  }
}
