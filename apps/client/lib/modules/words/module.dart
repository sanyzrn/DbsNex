import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_deck_cache.dart';
import 'words_reminder.dart';
import 'words_screen.dart';
import 'words_strings.dart';
import 'words_glance.dart';
import 'words_summary.dart';

import 'words_dates.dart';

/// «Word by Word» — an offline vocabulary box: capture the words you meet
/// with your own meanings, review them on a small deterministic ladder of
/// days, keep the history on this phone.
class WordsModule extends NexStoredModule {
  const WordsModule();

  @override
  String get id => 'words';

  @override
  IconData get icon => Icons.translate_outlined;

  @override
  NexHue get hue => NexHue.violet;

  @override
  NexModuleStrings get strings => wordsStrings;

  @override
  Widget screen(NexModuleStore store) => WordsScreen(store: store);

  /// As Nex starts and returns, the review reminder moves to the next day
  /// with words waiting (2.4.0).
  @override
  Future<void> keepUp(NexModuleStore store, AppLocalizations l10n) =>
      wordsArmReminder(store, l10n, preserveShown: true);

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => wordsGlance(store, l10n, now);

  /// On the home screen, the day's reviews are one line (2.8.5).
  ///
  /// The deck arrives through the shared parse cache: this runs on the home
  /// screen's module sweep, and the deck is the same deck that `keepUp` and
  /// the glance just parsed.
  @override
  Future<List<ModuleDue>> dues(
    NexModuleStore store,
    DateTime from,
    DateTime to,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(from) || today.isAfter(to)) return const [];
    final cards = wordsCardsFromRecords(await store.list('card'));
    final due = duesBetween(cards, DateTime(1970), today).length;
    if (due == 0) return const [];
    return [
      ModuleDue(
        id: 'words:${wordsIsoDay(today)}',
        recordKind: 'card',
        recordId: '',
        at: today,
        title: '',
        kind: 'words-review:$due',
      ),
    ];
  }

  @override
  String? dueLabel(AppLocalizations l10n, String kind) {
    if (!kind.startsWith('words-review:')) return null;
    final n = int.tryParse(kind.substring('words-review:'.length)) ?? 0;
    return strings.text(l10n, 'glanceReviewsToday', {'n': n});
  }
}
