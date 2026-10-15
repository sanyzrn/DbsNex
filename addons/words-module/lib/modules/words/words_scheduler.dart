/// The review schedule: one fixed ladder of days, one rule per answer,
/// everything computed from local calendar days.
///
/// **The ladder** is `[1, 3, 7, 14, 30, 60]` days. A card sits on a rung
/// (`step` 0..5). Nothing is spaced by a multiplier, an ease factor, a
/// jitter, or a claim to be FSRS: this is a modest, bounded,
/// deterministic policy, chosen on purpose.
///
/// **What each answer does** — computed from the review day, never from
/// the old due date, so an overdue card answered today is scheduled from
/// today:
///
/// | Answer | step | next interval |
/// |---|---|---|
/// | Again | 0 | ladder[0] = 1 day |
/// | Hard | unchanged | ladder[step] (the same interval again) |
/// | Good | step + 1 (max 5) | ladder at the new step |
/// | Easy | step + 2 (max 5) | ladder at the new step |
///
/// A card that reaches step 5 (a 60-day interval) carries the «learned»
/// mark. «Again» adds one lapse; nothing else counts lapses. Paused cards
/// are never scheduled and never enter a session.
///
/// **Calendar days, not 24-hour spans.** A due date is stored as a
/// date-only ISO string; adding days uses the `DateTime(year, month,
/// day + n)` constructor, which walks the calendar (over month ends, over
/// February, over years) and lands on local midnight — it cannot be
/// shifted by an hour the way `DateTime.add(Duration(days: n))` can when
/// a day changes length. Comparisons are plain string compares, which
/// `YYYY-MM-DD` orders correctly. This is also why the module shows
/// relative labels («in 3 days», «2 days overdue») instead of clock times.
///
/// There is no clock in here anywhere: [answer] takes the day it
/// happened, so the whole thing is testable against any day, including
/// leap days and year ends.
library;

import 'words_models.dart';
import 'words_dates.dart';

/// The ladder, index 0..5.
const List<int> wordsLadder = [1, 3, 7, 14, 30, 60];

/// The result of answering a card: the card as it now stands.
WordCard answerCard(WordCard card, WordsGrade grade, DateTime reviewedOn) {
  if (card.paused) return card;
  reviewedOn = reviewedOn.toLocal();
  final step = _atMost(card.step);
  final newStep = switch (grade) {
    // A miss starts the ladder over; it also counts as a lapse.
    WordsGrade.again => 0,
    // «Hard» repeats the current interval rather than shortening it.
    WordsGrade.hard => step,
    WordsGrade.good => _atMost(_atMost(card.step) + 1),
    WordsGrade.easy => _atMost(_atMost(card.step) + 2),
  };
  final intervalDays = switch (grade) {
    WordsGrade.again => wordsLadder[0],
    WordsGrade.hard => wordsLadder[_atMost(card.step)],
    _ => wordsLadder[newStep],
  };

  final atIso = reviewedOn.toIso8601String();
  final log = [...card.log, (at: atIso, grade: grade)];
  // The cap keeps records small; the counted history (reps, lapses) never
  // depends on it.
  final trimmed = log.length > WordCard.maxLog
      ? log.sublist(log.length - WordCard.maxLog)
      : log;

  return card.copyWith(
    step: newStep,
    due: isoDay(addDays(reviewedOn, intervalDays)),
    lapses: grade == WordsGrade.again ? _increment(card.lapses) : card.lapses,
    reps: _increment(card.reps),
    lastReviewIso: atIso,
    introducedOn: card.introducedOn.isNotEmpty
        ? card.introducedOn
        : card.isNew
        ? isoDay(reviewedOn)
        : _firstDay(card) ?? '',
    log: trimmed,
  );
}

/// The interval an answer would produce, in days — shown under each
/// button *before* it is pressed, so nobody has to guess.
int previewIntervalDays(WordCard card, WordsGrade grade) => switch (grade) {
  WordsGrade.again => wordsLadder[0],
  WordsGrade.hard => wordsLadder[_atMost(card.step)],
  WordsGrade.good => wordsLadder[_atMost(_atMost(card.step) + 1)],
  WordsGrade.easy => wordsLadder[_atMost(_atMost(card.step) + 2)],
};

/// Adds [days] calendar days to a date, landing on local midnight.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// The date-only ISO day of a moment, in its own timezone.
String isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// How many days from [fromDay] to [dueDay], signed: negative when the
/// card is overdue. Both are date-only ISO strings.
int daysUntil(String fromDay, String dueDay) {
  final from = wordsParseDay(fromDay);
  final due = wordsParseDay(dueDay);
  return from == null || due == null ? 0 : due.difference(from).inDays;
}

int _atMost(int step) => step.clamp(0, 5);
int _increment(int value) => value >= 9007199254740991
    ? 9007199254740991
    : value < 0
    ? 1
    : value + 1;

/// Builds a review session: the due cards first (most overdue first),
/// then new cards up to the day's remaining introduction allowance.
/// `introducedToday` counts cards whose first-ever answer was today, so
/// the cap follows the person across restarts, not the session.
({List<WordCard> due, List<WordCard> fresh}) buildSession({
  required List<WordCard> cards,
  required String todayIso,
  required int newPerDay,
  int sessionLimit = 20,
}) {
  final due = cards.where((card) => card.isDueOn(todayIso)).toList()
    ..sort((a, b) => a.due.compareTo(b.due));

  final freshAll = cards.where((card) => !card.paused && card.isNew).toList()
    ..sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));

  final introducedToday = cards
      .where((card) => !card.isNew && _firstDay(card) == todayIso)
      .length;
  final allowance = newPerDay <= 0
      ? freshAll.length
      : newPerDay - introducedToday;

  final selectedDue = sessionLimit <= 0 ? due : due.take(sessionLimit).toList();
  final remaining = sessionLimit <= 0
      ? freshAll.length
      : sessionLimit - selectedDue.length;
  final fresh = freshAll
      .take(allowance < 0 ? 0 : allowance)
      .take(remaining)
      .toList();
  return (due: selectedDue, fresh: fresh);
}

String? _firstDay(WordCard card) => wordsParseDay(card.introducedOn) != null
    ? card.introducedOn
    : card.log.isEmpty
    ? null
    : wordsStampDay(card.log.first.at);

/// The relative words for a due day: «today», «tomorrow», «in N days»,
/// «N days overdue» — the numbers arrive already formatted by the caller.
({int days, bool overdue, bool today, bool tomorrow}) dueWords(
  String todayIso,
  String dueDay,
) {
  final days = daysUntil(todayIso, dueDay);
  return (
    days: days < 0 ? -days : days,
    overdue: days < 0,
    today: days == 0,
    tomorrow: days == 1,
  );
}
