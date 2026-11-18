/// Practice that teaches from the person's own words: forgiving typing,
/// multiple choice drawn from the same deck, the daily goal and the week
/// behind it. No widgets here, so every rule can be tested on its own.
library;

import 'dart:math' as math;

import 'words_dates.dart';
import 'words_models.dart';

/// The three ways a card can be asked in a review.
enum WordsExercise { flashcard, type, choose }

/// One answer, normalised for comparison: the forms a person types on a
/// Persian or Arabic keyboard, the case of an English word, the spaces
/// between words and the marks above them stop mattering. Nothing is
/// invented — only what the person actually wrote is compared.
///
/// - Arabic and Persian letters that name the same sound are one letter
///   (ي/ی, ك/ک, ة/ه, أ/إ/آ/ٱ/ا, ؤ/و, ئ/ی);
/// - the vowel marks and the tatweel are dropped, and the zero-width
///   non-joiner disappears rather than becoming a space;
/// - Persian and Arabic digits read as the same digits;
/// - punctuation becomes a space, runs of spaces fold, and case folds.
String wordsNormalize(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      // A ZWNJ inside «می‌روم» is part of the word, not a gap in it.
      case 0x200C || 0x200D || 0x0640:
        continue;
      // Harakat, Quranic marks and superscript alef.
      case >= 0x064B && <= 0x065F || 0x0670 || (>= 0x06D6 && <= 0x06ED):
        continue;
      case 0x064A || 0x0626:
        buffer.write('ی');
      case 0x0643:
        buffer.write('ک');
      case 0x0629 || 0x06C0:
        buffer.write('ه');
      case 0x0623 || 0x0625 || 0x0622 || 0x0671:
        buffer.write('ا');
      case 0x0624:
        buffer.write('و');
      // Arabic-Indic and Persian digits become plain digits.
      case >= 0x0660 && <= 0x0669:
        buffer.writeCharCode(0x30 + rune - 0x0660);
      case >= 0x06F0 && <= 0x06F9:
        buffer.writeCharCode(0x30 + rune - 0x06F0);
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

/// Whether [typed] is one of the answers [expected] holds. A meaning may
/// carry several senses on their own lines, and any of them is right.
bool wordsAnswerMatches(String typed, String expected) {
  final answer = wordsNormalize(typed);
  if (answer.isEmpty) return false;
  for (final line in expected.split(RegExp(r'[\r\n]+'))) {
    if (wordsNormalize(line) == answer) return true;
  }
  return false;
}

/// The side of [card] that is asked for: the meaning, or the word itself
/// when the meaning is shown first.
String wordsAnswerOf(WordCard card, {required bool reverse}) =>
    reverse ? card.headword : card.meaning;

/// The side of [card] that is shown: the word, or the meaning when the
/// meaning is asked first. A card with no meaning always asks forward.
String wordsPromptOf(WordCard card, {required bool reverse}) =>
    reverse && card.meaning.isNotEmpty ? card.meaning : card.headword;

/// Up to [count] choices for [card]: the right answer and wrong ones drawn
/// from the same deck first, then from the rest of the person's words. The
/// order is decided by the card and [salt], not by the moment, so the same
/// card in the same session shows the same choices.
List<String> wordsChoices(
  WordCard card,
  List<WordCard> pool, {
  required bool reverse,
  int count = 4,
  int salt = 0,
}) {
  final correct = wordsAnswerOf(card, reverse: reverse).trim();
  final correctKey = wordsNormalize(correct);
  if (correctKey.isEmpty) return const [];
  final seen = <String>{correctKey};
  final sameDeck = <String>[];
  final elsewhere = <String>[];
  for (final other in pool) {
    if (other.id == card.id || other.paused) continue;
    final text = wordsAnswerOf(other, reverse: reverse).trim();
    final key = wordsNormalize(text);
    if (key.isEmpty || !seen.add(key)) continue;
    (card.deckId.isNotEmpty && other.deckId == card.deckId
            ? sameDeck
            : elsewhere)
        .add(text);
  }
  final wanted = math.max(1, count - 1);
  final picked = <String>[
    ..._shuffled(sameDeck, '${card.id}:$salt:deck'),
    ..._shuffled(elsewhere, '${card.id}:$salt:all'),
  ].take(wanted).toList();
  return _shuffled([correct, ...picked], '${card.id}:$salt:options');
}

/// A stable order for [items], seeded by [seed] — `List.shuffle` is not
/// reproducible between runs, and options that move on every rebuild are
/// hard to tap.
List<String> _shuffled(List<String> items, String seed) {
  final ranked =
      [
        for (var i = 0; i < items.length; i++)
          (key: _fnv('$seed:${items[i]}'), i: i),
      ]..sort(
        (a, b) => a.key == b.key ? a.i.compareTo(b.i) : a.key.compareTo(b.key),
      );
  return [for (final entry in ranked) items[entry.i]];
}

/// FNV-1a over the seed's code units: small, stable and platform-free.
int _fnv(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// How many answers the cards carry on [dayIso] — the day the answer was
/// given, read from the log's local day.
int wordsReviewsOn(Iterable<WordCard> cards, String dayIso) {
  var reviews = 0;
  for (final card in cards) {
    for (final entry in card.log) {
      if (wordsStampDay(entry.at) == dayIso) reviews++;
    }
  }
  return reviews;
}

/// The seven days ending on [today], oldest first, with how many answers
/// each one holds and how many of them were «again».
List<({String iso, int reviews, int again})> wordsWeek(
  Iterable<WordCard> cards,
  DateTime today,
) {
  final reviews = <String, int>{};
  final again = <String, int>{};
  for (final card in cards) {
    for (final entry in card.log) {
      final day = wordsStampDay(entry.at);
      if (day == null) continue;
      reviews[day] = (reviews[day] ?? 0) + 1;
      if (entry.grade == WordsGrade.again) {
        again[day] = (again[day] ?? 0) + 1;
      }
    }
  }
  return [
    for (var back = 6; back >= 0; back--)
      () {
        final day = DateTime(today.year, today.month, today.day - back);
        final iso = wordsIsoDay(day);
        return (iso: iso, reviews: reviews[iso] ?? 0, again: again[iso] ?? 0);
      }(),
  ];
}

/// What the progress view says about the whole collection.
({int total, int learned, int due, int paused, int reviews, int again})
wordsProgressSummary(
  Iterable<WordCard> cards, {
  required String todayIso,
  required DateTime today,
}) {
  var total = 0;
  var learned = 0;
  var due = 0;
  var paused = 0;
  for (final card in cards) {
    total++;
    if (card.paused) {
      paused++;
      continue;
    }
    if (!card.isNew && card.step >= 5) learned++;
    if (card.isDueOn(todayIso)) due++;
  }
  final week = wordsWeek(cards, today);
  return (
    total: total,
    learned: learned,
    due: due,
    paused: paused,
    reviews: week.fold(0, (sum, day) => sum + day.reviews),
    again: week.fold(0, (sum, day) => sum + day.again),
  );
}
