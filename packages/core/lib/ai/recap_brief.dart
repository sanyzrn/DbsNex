/// Turning what a model sent back into the briefing the app shows.
///
/// The recap used to be a paragraph, and a paragraph is the wrong shape for
/// what it is for. Somebody opening a notes app in the morning is not reading
/// an essay about their week — they are checking whether anything is waiting
/// on them, and prose makes them read the whole thing to find out. Three
/// lines, one thing each, is the shape an assistant uses when it tells you
/// what your day has in it.
///
/// A model asked for lines will mostly send lines, and will sometimes send a
/// numbered list, or a heading, or one line with a bullet in front of it, or
/// eight lines when it was asked for three. Fixing that in the prompt alone
/// is asking every model this app talks to — including the small local ones —
/// to be well behaved every single time. Fixing it here is arithmetic.
///
/// Pure, so it is tested without a network: the things that go wrong with a
/// generated list are all things that can be written down as input.
library;

/// The bullet and numbering shapes a model reaches for when it is asked for a
/// list and told not to decorate it.
final _leader = RegExp(r'^\s*(?:[-*•·–—]+|\d+[.)]|[»>]+)\s*');

/// A line that is only punctuation, only digits, or only a picture. A model
/// padding to the line count it was given produces these.
final _empty = RegExp(r'^[\s\p{P}\p{S}\p{N}]*$', unicode: true);

/// Markdown emphasis wrapped around a whole line.
///
/// Stripped at the ends only, and stripped at all because this text is shown
/// as plain text in three places — the card, the home-screen widget and the
/// morning notification — none of which render markdown. `**Due soon**`
/// arrives here as `Due soon**`, because the leading pair has already been
/// eaten by [_leader] as though it were a bullet.
final _emphasis = RegExp(r'^[*_~`]+|[*_~`]+$');

/// A line wrapped in emphasis from end to end — `**Today**`, `__Reminders__`.
///
/// Recorded before the markers are taken off, because by then it is
/// indistinguishable from a line that never had any.
final _wrapped = RegExp(r'^([*_~]{1,3})[^*_~].*\1$');

/// Reshapes [reply] into at most [maxLines] lines of at most [maxWords] each.
///
/// Null when there is nothing usable left, which the caller treats the same
/// as no answer at all: the card keeps whatever it had rather than replacing
/// a good recap with a bad one.
String? nexTidyBrief(
  String? reply, {
  int maxLines = 4,
  int maxWords = 16,
}) {
  final source = reply?.trim();
  if (source == null || source.isEmpty) return null;

  final lines = <String>[];
  for (final raw in source.split('\n')) {
    if (lines.length >= maxLines) break;
    // Collapsed *within* the line only. The newlines are the structure here,
    // which is exactly what the old word-clamp destroyed by flattening every
    // run of whitespace in the whole reply.
    final line = raw.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (line.isEmpty) continue;
    final wrapped = _wrapped.hasMatch(line);
    final stripped = line
        .replaceFirst(_leader, '')
        .replaceAll(_emphasis, '')
        .trim();
    if (stripped.isEmpty || _empty.hasMatch(stripped)) continue;
    // A heading the prompt asked for none of — "Today:", "**Reminders**" —
    // is a line with no content of its own.
    if (_isHeading(stripped, wrapped: wrapped)) continue;
    lines.add(_clampWords(stripped, maxWords));
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

/// Whether a line is a label for the lines under it rather than one of them.
///
/// Kept narrow on purpose. "Due soon:" is a heading; "Call the plumber: he
/// left a message" is not, and the difference is whether anything follows the
/// colon.
///
/// [wrapped] says the line was bold or italic from end to end, which is the
/// other way a model labels a group — but only a *short* one. Some models
/// emphasise every line they write, and treating "**Call the plumber before
/// Friday**" as a label would throw away the briefing to keep its heading.
/// Two words is the width of "Due soon" and narrower than any real line.
bool _isHeading(String line, {required bool wrapped}) {
  if (line.startsWith('#')) return true;
  if (line.endsWith(':') || line.endsWith('：')) return true;
  return wrapped && line.split(' ').length <= 2;
}

/// Cuts one line to [maxWords], preferring to stop where a sentence does.
String _clampWords(String line, int maxWords) {
  final words = line.split(' ');
  if (words.length <= maxWords) return line;
  final cut = words.take(maxWords).join(' ');
  final stop = cut.lastIndexOf(RegExp(r'[.!?…؟۔]'));
  if (stop > cut.length ~/ 2) return cut.substring(0, stop + 1);
  return '$cut…';
}

/// How many lines a briefing may have, given how much there is to brief on.
///
/// A ceiling, not a target: the prompt says "at most", and on a quiet day one
/// line is the honest answer. A card that fills the same four lines every
/// morning is a card people stop reading — which is the same reasoning the
/// word budget it replaces was built on, applied to the shape that replaced
/// it.
int nexBriefLines(int noteCount) => switch (noteCount) {
  <= 2 => 2,
  <= 6 => 3,
  _ => 4,
};
