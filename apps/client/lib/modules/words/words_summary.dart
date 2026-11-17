/// The shared shapes of "Shared across modules" (`docs/18-module-kit.md`,
/// rules 1 and 4), copied here because the kit does not carry them yet —
/// `ModuleDue` and `ModuleSummary`, with the fields that section names, so
/// the kit can replace this file with one move later.
///
/// Word by Word has no money, so `amountRial` is never set, and nothing it
/// keeps is health or money detail, so `private` stays false.
library;

import 'package:nex_client/modules/module_api.dart';

import 'words_dates.dart';
import 'words_models.dart';

/// One thing this module has falling due: a word's next review day.
class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    this.amountRial,
    this.done = false,
    this.private = false,
  });

  /// Stable across calls: the card and the day it falls on.
  final String id;
  final String recordKind;
  final String recordId;

  /// Local midnight of the day it falls due.
  final DateTime at;
  final String title;

  /// The module's word for it — `review` here.
  final String kind;
  final int? amountRial;
  final bool done;
  final bool private;
}

/// Everything Word by Word has falling due between [from] and [to],
/// oldest first. Paused cards and cards never answered wait for nothing;
/// a card whose due day is unreadable is left out rather than guessed at.
List<ModuleDue> duesBetween(
  Iterable<WordCard> cards,
  DateTime from,
  DateTime to,
) {
  final first = wordsIsoDay(from);
  final last = wordsIsoDay(to);
  final dues = <ModuleDue>[];
  for (final card in cards) {
    if (card.paused || card.isNew) continue;
    final day = wordsParseDay(card.due);
    if (day == null) continue;
    if (card.due.compareTo(first) < 0 || card.due.compareTo(last) > 0) {
      continue;
    }
    dues.add(
      ModuleDue(
        id: '${card.id}@${card.due}',
        recordKind: 'card',
        recordId: card.id,
        at: DateTime(day.year, day.month, day.day),
        title: card.headword,
        kind: 'review',
      ),
    );
  }
  dues.sort((a, b) => a.at.compareTo(b.at));
  return dues;
}

/// One line about a record, for the day the person lets the app mention
/// their words. Nothing reads it yet.
class ModuleSummary {
  const ModuleSummary({required this.title, this.detail, this.private = false});

  final String title;
  final String? detail;
  final bool private;
}

/// A card as one line: the word, then its first meaning and its language.
ModuleSummary? summarize(ModuleRecord record) {
  if (record.kind != 'card') return null;
  final card = WordCard.fromRecord(record.id, record.body);
  if (card.headword.isEmpty) return null;
  final firstSense = card.meaning
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final detail = [
    if (firstSense.isNotEmpty) firstSense,
    if (card.language.isNotEmpty) card.language,
  ].join(' · ');
  return ModuleSummary(
    title: card.headword,
    detail: detail.isEmpty ? null : detail,
  );
}
