/// One word's own page: its fields, its review progress, its pause — and,
/// when the person asks for it, its deletion with a time-limited Undo
/// that brings back the card *with its whole history*.
///
/// Editing only ever touches the words. Scheduling (step, due, lapses,
/// reps, log) is carried over untouched — fixing a typo never forgets the
/// work already done.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_fields.dart';
import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';
import 'words_dates.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
part 'words_card_logic.dart';
part 'words_card_repair.dart';

class WordsCardPage extends StatefulWidget {
  const WordsCardPage({super.key, required this.store, this.card});

  final NexModuleStore store;

  /// The card being viewed, or null to write a new one.
  final WordCard? card;

  @override
  State<WordsCardPage> createState() => _WordsCardPageState();
}

class _WordsCardPageState extends State<WordsCardPage> with _WordsCardLogic {
  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final existing = widget.card != null;
    return DraftGuard(
      draft: _draft,
      busy: () => _saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Scaffold(
          appBar: NexAppBar(
            title: Text(strings(context, existing ? 'wordLabel' : 'addWord')),
            actions: [
              if (existing)
                IconButton(
                  key: const ValueKey('words-card-delete'),
                  tooltip: AppLocalizations.of(context).delete,
                  onPressed: _saving ? null : () => unawaited(_delete()),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: _restoring
              ? const Center(child: NexInlineSpinner())
              : _draftLoadFailed
              ? NexEmptyState(
                  icon: Icons.cloud_off_outlined,
                  message: strings(context, 'draftLoadError'),
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => unawaited(_restore()),
                        child: Text(strings(context, 'retry')),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_cancel()),
                        child: Text(AppLocalizations.of(context).cancel),
                      ),
                    ],
                  ),
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                  ),
                  children: [
                    const SizedBox(height: NexSpacing.md),
                    WordsWordField(
                      controller: _headword,
                      focusNode: _wordFocus,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsAutoField(
                      controller: _language,
                      label: strings(context, 'languageLabel'),
                      hint: strings(context, 'languageHint'),
                      fieldKey: const ValueKey('words-field-language'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsNoteField(
                      controller: _meaning,
                      label: strings(context, 'meaningLabel'),
                      hint: strings(context, 'meaningHint'),
                      fieldKey: const ValueKey('words-field-meaning'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsNoteField(
                      controller: _example,
                      label: strings(context, 'exampleLabel'),
                      fieldKey: const ValueKey('words-field-example'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsNoteField(
                      controller: _note,
                      label: strings(context, 'noteLabel'),
                      fieldKey: const ValueKey('words-field-note'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsAutoField(
                      controller: _tag,
                      label: strings(context, 'tagLabel'),
                      fieldKey: const ValueKey('words-field-tag'),
                    ),
                    if (existing) ...[
                      const SizedBox(height: NexSpacing.md),
                      _progressPanel(context, theme),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    FilledButton.icon(
                      key: const ValueKey('words-card-save'),
                      onPressed: _saving ? null : () => unawaited(_save()),
                      icon: const Icon(Icons.check),
                      label: Text(AppLocalizations.of(context).save),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    TextButton(
                      key: const ValueKey('words-card-cancel'),
                      onPressed: () => unawaited(_cancel()),
                      child: Text(strings(context, 'discardDraft')),
                    ),
                    Text(
                      strings(context, 'draftHint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: NexSpacing.md),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _progressPanel(BuildContext context, ThemeData theme) {
    final strings = wordsStrings;
    final scheme = theme.colorScheme;
    final todayIso = isoDay(DateTime.now());
    final words = dueWords(todayIso, _card.due);
    final nextReview = _card.isNew
        ? strings(context, 'neverReviewed')
        : wordsParseDay(_card.due) == null
        ? strings(context, 'scheduleUnknown')
        : words.today
        ? strings(context, 'dueToday')
        : words.overdue
        ? (words.days == 1
              ? strings(context, 'dueOverdueOne')
              : strings(context, 'dueOverdue', {'count': words.days}))
        : words.tomorrow
        ? strings(context, 'dueTomorrow')
        : strings(context, 'dueInDays', {'count': words.days});
    return NexPanel(
      title: strings(context, 'progressLabel'),
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings(context, 'statsLine', {
              'reps': _card.reps,
              'lapses': _card.lapses,
              'step': _card.step,
            }),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            '${strings(context, 'nextDue')}: $nextReview',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!_card.isNew && wordsParseDay(_card.due) == null)
            TextButton(
              key: const ValueKey('words-card-repair-date'),
              onPressed: _saving ? null : () => unawaited(_repairDue()),
              child: Text(strings(context, 'repairDueAction')),
            ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'createdLine', {'when': _createdWhen(context)}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            key: const ValueKey('words-card-pause'),
            contentPadding: EdgeInsets.zero,
            title: Text(strings(context, 'pausedLabel')),
            subtitle: Text(
              strings(context, 'pausedHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            value: _card.paused,
            onChanged: _saving ? null : (_) => unawaited(_togglePaused()),
          ),
        ],
      ),
    );
  }

  /// «Added today / yesterday / N days ago», and beyond a month the day
  /// itself through the shared label — which follows the person's calendar
  /// (Jalali for Persian) and their digits. Storage stays an ISO instant.
  String _createdWhen(BuildContext context) {
    final strings = wordsStrings;
    final created = wordsValidStamp(_card.createdAtIso) == null
        ? null
        : DateTime.tryParse(_card.createdAtIso)?.toLocal();
    if (created == null) return strings(context, 'whenUnknown');
    final shownDate = nexModuleDateLabel(context, created);
    final now = DateTime.now();
    final createdDay = DateTime.utc(created.year, created.month, created.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    final days = today.difference(createdDay).inDays;
    if (days == 0) return strings(context, 'whenToday');
    if (days < 0) return strings(context, 'whenDate', {'date': shownDate});
    if (days == 1) return strings(context, 'whenYesterday');
    return days < 30
        ? strings(context, 'whenDaysAgo', {'count': days})
        : strings(context, 'whenDate', {'date': shownDate});
  }
}
