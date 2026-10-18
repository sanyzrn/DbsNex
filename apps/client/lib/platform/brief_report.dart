import 'package:intl/intl.dart';
import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import '../l10n/relative_span.dart';
import 'package:nex_ai/cloud.dart';

/// The brief the app writes itself, from what it already knows.
///
/// Three groups in the order somebody actually wants them — what has slipped,
/// what is coming, what is half-done — one line each, and no line that is not
/// a fact already in the database. It is the whole of the plain-report
/// style, and the part the two styles with a model in them state for
/// themselves before the model is asked for anything.
///
/// Null rather than a sentence when nothing is waiting. A quiet day is a real
/// answer and the card already has a line for it; inventing "you have 4
/// notes" to fill the space is the habit this whole setting exists to break.
///
/// The [maxLines] budget is spent from the top, so a long list of overdue
/// items can take the whole card. That is the right failure: a brief that
/// drops the third overdue bill to make room for an unticked shopping list
/// has its priorities the wrong way round.
///
/// A reminder coming up is said by its day and time — "call the plumber —
/// tomorrow at 09:00" — not as a countdown (2.1.6). Most reminders are when
/// somebody means to do a thing, not a deadline, and "due in 15 hours" said
/// the opposite; it was also wrong for most of the hour a brief stays on the
/// card. [clock] writes the time the way the phone does; left out, it is
/// 24-hour in the interface's digits.
String? nexBriefReport(
  NexBriefFacts facts,
  AppLocalizations l10n, {
  int maxLines = 4,
  DateTime? now,
  String Function(DateTime local)? clock,
}) {
  if (facts.nothingWaiting || maxLines <= 0) return null;
  final at = now ?? DateTime.now();
  final persian = l10n.localeName == 'fa';
  String time(DateTime local) =>
      clock?.call(local) ??
      nexDigits(
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
        persian: persian,
      );
  final lines = <String>[];

  void add(String line) {
    if (lines.length < maxLines) lines.add(line);
  }

  for (final entry in facts.overdue) {
    add(
      '⏰ ${l10n.briefLineOverdue(entry.title, nexRelativeSpan(l10n, at.difference(entry.dueAt!)))}',
    );
  }
  for (final entry in facts.dueSoon) {
    final due = entry.dueAt!.toLocal();
    final days = _calendarDays(at.toLocal(), due);
    // A standing commitment — the rent, a renewal — is said by how far off it
    // is, by the calendar: its time of day is mostly the hour it was entered.
    // A reminder is said by when it is. Past six days a weekday would name
    // today's, so the count comes back.
    final when = entry.recurring || days >= 7
        ? null
        : days <= 0
        ? l10n.briefWhenToday(time(due))
        : days == 1
        ? l10n.briefWhenTomorrow(time(due))
        : l10n.briefWhenOn(
            DateFormat.EEEE(l10n.localeName).format(due),
            time(due),
          );
    add(
      when != null
          ? '📅 ${l10n.briefLineAt(entry.title, when)}'
          : '📅 ${l10n.briefLineDue(entry.title, days >= 1 ? l10n.spanDays(days) : nexRelativeSpan(l10n, entry.dueAt!.difference(at)))}',
    );
  }
  for (final entry in facts.unfinished) {
    add(
      '☑️ ${l10n.briefLineChecklist(entry.title, entry.remaining!, entry.total!)}',
    );
  }

  return lines.isEmpty ? null : lines.join('\n');
}

/// Whole calendar days from [from] to [to], through UTC midnights so a clock
/// change in between cannot shorten a day.
int _calendarDays(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The facts actually written alongside a model reply, without relative ages.
String nexBriefFactsSignature(NexBriefFacts facts, {required int maxLines}) => [
  for (final entry in [
    for (final value in facts.overdue) ('overdue', value),
    for (final value in facts.dueSoon) ('soon', value),
    for (final value in facts.unfinished) ('unfinished', value),
  ].take(maxLines))
    '${entry.$1}|${entry.$2.title}|${entry.$2.dueAt?.toUtc().toIso8601String()}|'
        '${entry.$2.remaining}|${entry.$2.total}',
].join('\n');

/// Everything a brief was made from, as one string to fingerprint.
///
/// The notes are the obvious half and were the only half for a while, which
/// was the bug: the recap is cached against what it was written from, so a
/// brief written under one style, tone, length or language stayed on the card
/// after any of them changed. The setting appeared to do nothing — nothing
/// had asked for a new brief.
///
/// The headline beside the brief has always keyed its own cache on the
/// language, which is why choosing English turned the greeting English
/// immediately and left a Persian brief sitting under it.
///
/// Separate from `recapFingerprint`, which hashes this: what goes into a
/// brief is a fact about briefs, and hashing is a fact about hashing.
String nexBriefSignature({
  required String source,
  required NexBriefStyle style,
  required AiResponseStyle tone,
  required NexBriefLength length,
  required AiOutputLanguage language,
  required String instruction,
}) =>
    '${style.wireName}|${tone.wireName}|${length.wireName}'
    '|${language.wireName}|${instruction.trim()}\n$source';
