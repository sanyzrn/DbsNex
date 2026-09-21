import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import '../l10n/relative_span.dart';
import 'ai_provider.dart';

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
String? nexBriefReport(
  NexBriefFacts facts,
  AppLocalizations l10n, {
  int maxLines = 4,
  DateTime? now,
}) {
  if (facts.nothingWaiting || maxLines <= 0) return null;
  final at = now ?? DateTime.now();
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
    add(
      '📅 ${l10n.briefLineDue(entry.title, nexRelativeSpan(l10n, entry.dueAt!.difference(at)))}',
    );
  }
  for (final entry in facts.unfinished) {
    add(
      '☑️ ${l10n.briefLineChecklist(entry.title, entry.remaining!, entry.total!)}',
    );
  }

  return lines.isEmpty ? null : lines.join('\n');
}

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
