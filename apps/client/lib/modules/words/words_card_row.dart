/// One word in the home list: the headword in its own direction, a
/// one-line preview of the meaning, and the small status line — language,
/// where the card stands (new, learned, today, in N days, N days
/// overdue, paused), and its tag.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_strings.dart';
import 'words_visuals.dart';

class WordsCardRow extends StatelessWidget {
  const WordsCardRow({
    super.key,
    required this.card,
    required this.todayIso,
    required this.onTap,
  });

  final WordCard card;
  final String todayIso;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _status(context, strings);
    final due = !card.paused && !card.isNew && card.due.isNotEmpty
        ? dueWords(todayIso, card.due)
        : null;
    final waiting = due != null && (due.today || due.overdue);
    final start = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
    // A card of its own (2.4.0): the language as a badge, the word large in
    // its own direction with its meaning under it, and how well it is known
    // as a small meter beside what comes next.
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side: BorderSide(
          color: waiting
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('words-card-${card.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm + 4,
          ),
          child: Row(
            children: [
              WordsLanguageBadge(language: card.language),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Each line in its own direction, all at the page's
                    // start edge: an English word in a Persian list lined up
                    // with its Persian meaning, not on the far side of it.
                    _line(
                      context,
                      card.headword,
                      start,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: card.paused ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (card.meaning.isNotEmpty)
                      _line(
                        context,
                        card.meaning,
                        start,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (card.tag.isNotEmpty || card.language.isNotEmpty)
                      Text(
                        [
                          if (card.language.isNotEmpty) card.language,
                          if (card.tag.isNotEmpty) card.tag,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: NexSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (card.paused)
                    Icon(
                      Icons.pause_circle_outline,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    )
                  else
                    WordsStrength(card: card),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: waiting ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: waiting ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One line in its own direction, set at the page's start edge.
  static Widget _line(
    BuildContext context,
    String text,
    TextAlign start, {
    TextStyle? style,
  }) => Directionality(
    textDirection: nexDirectionOf(text) ?? Directionality.of(context),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: start,
      style: style,
    ),
  );

  String _status(BuildContext context, NexModuleStrings strings) {
    if (card.paused) return strings(context, 'filterPaused');
    if (card.isNew) return strings(context, 'statusNew');
    if (card.due.isEmpty) return strings(context, 'scheduleUnknown');
    if (card.step >= 5) return strings(context, 'learnedMark');
    final words = dueWords(todayIso, card.due);
    if (words.today) return strings(context, 'dueToday');
    if (words.overdue) {
      return words.days == 1
          ? strings(context, 'dueOverdueOne')
          : strings(context, 'dueOverdue', {'count': words.days});
    }
    if (words.tomorrow) return strings(context, 'dueTomorrow');
    return strings(context, 'dueInDays', {'count': words.days});
  }
}
