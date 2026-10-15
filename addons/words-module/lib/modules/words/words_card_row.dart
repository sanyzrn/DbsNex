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
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('words-card-${card.id}'),
        onTap: onTap,
        title: NexTextSurface(
          card.headword,
          maxLines: 1,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (card.meaning.isNotEmpty)
              NexTextSurface(
                card.meaning,
                maxLines: 1,
                style: theme.textTheme.bodySmall,
              ),
            Text(
              [
                if (card.language.isNotEmpty) card.language,
                status,
                if (card.tag.isNotEmpty) card.tag,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: card.paused
            ? Icon(Icons.pause_circle_outline, color: scheme.onSurfaceVariant)
            : null,
      ),
    );
  }

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
