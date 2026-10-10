import 'package:nex_core/nex_core.dart';

/// What fits in the on-device model's context window.
///
/// LiteRT-LM runs Gemma with a window of 4,096 tokens, and the plugin that
/// drives it offers no way to make it larger — nor would a larger one fit a
/// phone's memory. The cloud path never had to count: its windows are tens
/// of times bigger. The phone did, and did not: the assistant's rules, the
/// action protocol, twenty recent notes, eight found notes and the whole
/// conversation went over together, and once that passed 4,096 the runtime
/// refused every message with "Input token ids are too long" — which the
/// chat showed as a model that "would not start".
///
/// Counting is an estimate, not the model's tokenizer, which only exists in
/// native code. It errs high on purpose: Persian and Arabic script costs
/// Gemma's tokenizer more per character than Latin text does, and an
/// estimate that is too generous fails the same way the old code did.
abstract final class LocalBudget {
  /// The model's whole window, input and answer together.
  static const window = 4096;

  /// What a request may use, leaving the rest for the answer.
  static const input = 2800;

  /// Roughly how many tokens [text] costs the on-device model.
  ///
  /// Three rates. Persian and Arabic script, 0.6 a character. Letters, digits
  /// and spaces, 0.33. Everything else — brackets, operators, punctuation,
  /// emoji — 0.6 too (AI-12): a tokenizer seldom merges symbols the way it
  /// merges letters, and a note full of code or JSON costs far more than
  /// 0.33 a character, which let a code-heavy library past the window.
  static int estimate(String text) {
    var dense = 0;
    var plain = 0;
    for (final rune in text.runes) {
      if (_isArabicScript(rune) || !_isPlain(rune)) {
        dense++;
      } else {
        plain++;
      }
    }
    return (dense * 0.6 + plain * 0.33).ceil();
  }

  /// A Latin letter, a digit or whitespace: what a tokenizer packs tightly.
  static bool _isPlain(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      rune == 0x20 ||
      rune == 0x0A ||
      rune == 0x09 ||
      // Ordinary punctuation inside prose: stays at the prose rate.
      rune == 0x2E ||
      rune == 0x2C ||
      rune == 0x27 ||
      // Accented Latin letters.
      (rune >= 0xC0 && rune <= 0x24F);

  static bool _isArabicScript(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0xFB50 && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);

  /// [text] cut to about [tokens], at a line or a word where it can be, with
  /// an ellipsis to say so. Unchanged when it already fits.
  static String clip(String text, int tokens) {
    if (tokens <= 0) return '';
    if (estimate(text) <= tokens) return text;
    var low = 0;
    var high = text.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (estimate(text.substring(0, mid)) + 1 <= tokens) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    var cut = text.substring(0, low);
    final space = cut.lastIndexOf(RegExp(r'\s'));
    if (space > cut.length * 0.7) cut = cut.substring(0, space);
    return '${cut.trimRight()}…';
  }

  /// A conversation cut to fit beside [reserved] tokens of instructions:
  /// the newest turns kept whole for as far back as they fit, every turn no
  /// longer than [perTurn], and nothing older than a turn that did not fit.
  ///
  /// The newest question always stays, clipped if it must be — answering
  /// a shortened question beats refusing it. A conversation never starts
  /// with the assistant's own words: a reply whose question was dropped is
  /// dropped with it.
  ///
  /// A lookup's findings (`<<<NOTES` … `NOTES>>>`) are clipped like any
  /// turn, and keep their closing marker so they still read as data.
  static List<ChatMessage> fitTurns(
    List<ChatMessage> turns, {
    required int reserved,
    int budget = input,
    int perTurn = 900,
  }) {
    if (turns.isEmpty) return const [];
    var left = budget - reserved;
    final kept = <ChatMessage>[];
    for (var i = turns.length - 1; i >= 0; i--) {
      final turn = turns[i];
      final newest = kept.isEmpty;
      final limit = newest
          ? (left < perTurn ? (left > 120 ? left : 120) : perTurn)
          : perTurn;
      final content = _clipTurn(turn.content, limit);
      final cost = estimate(content);
      if (!newest && cost > left) break;
      kept.add(ChatMessage(role: turn.role, content: content));
      left -= cost;
    }
    final ordered = kept.reversed.toList();
    while (ordered.length > 1 && ordered.first.role == ChatRole.assistant) {
      ordered.removeAt(0);
    }
    return ordered;
  }

  static String _clipTurn(String content, int tokens) {
    if (estimate(content) <= tokens) return content;
    const open = '<<<NOTES\n';
    const close = '\nNOTES>>>';
    if (content.startsWith(open) && content.endsWith(close)) {
      final inner = content.substring(
        open.length,
        content.length - close.length,
      );
      final room = tokens - estimate(open) - estimate(close);
      return '$open${clip(inner, room)}$close';
    }
    return clip(content, tokens);
  }

  /// The notes context cut to about [tokens]: each note's line kept short,
  /// the notes found for the question kept before the recent ones the app
  /// volunteered, and as many of each as fit, best first.
  ///
  /// [context] is what the chat sheet builds: the volunteered lines, then a
  /// blank line, a heading, and the found lines.
  static String fitNotes(String context, int tokens, {int perNote = 90}) {
    if (tokens <= 0 || context.trim().isEmpty) return '';
    const heading = 'Notes matching the latest question, best match first:';
    final at = context.indexOf(heading);
    final volunteered = (at < 0 ? context : context.substring(0, at))
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final found = at < 0
        ? const <String>[]
        : context
              .substring(at + heading.length)
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList();

    // One note and nothing found beside it is the chat about one note
    // (AI-04): it gets the whole room, not one line's ninety tokens.
    if (found.isEmpty && volunteered.length == 1) perNote = tokens;
    var left = tokens;
    final keptFound = <String>[];
    for (final line in found) {
      final short = clip(line, perNote);
      final cost = estimate(short) + 1;
      if (cost > left) break;
      keptFound.add(short);
      left -= cost;
    }
    if (keptFound.isNotEmpty) left -= estimate(heading) + 2;
    final keptRecent = <String>[];
    for (final line in volunteered) {
      final short = clip(line, perNote);
      final cost = estimate(short) + 1;
      if (cost > left) break;
      keptRecent.add(short);
      left -= cost;
    }
    return [
      if (keptRecent.isNotEmpty) keptRecent.join('\n'),
      if (keptFound.isNotEmpty) '$heading\n${keptFound.join('\n')}',
    ].join('\n\n');
  }
}
