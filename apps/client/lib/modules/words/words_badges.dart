/// The small marks a word wears: how far up the ladder it stands, the
/// two letters of its language, and the rungs of its own page.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_visuals.dart';

/// Five short bars, filled to how far up the ladder a word is; an outline
/// for a new one.
class WordsStrength extends StatelessWidget {
  const WordsStrength({super.key, required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = wordsStageOf(card);
    final filled = card.isNew ? 0 : math.min(5, card.step + 1);
    final color = card.paused
        ? scheme.outline
        : stage == WordsStage.fresh
        ? scheme.primary
        : wordsStageColor(stage);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 4,
            height: 6.0 + i * 2.5,
            decoration: BoxDecoration(
              color: i < filled ? color : null,
              border: i < filled
                  ? null
                  : Border.all(color: scheme.outline.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(NexRadius.xs),
            ),
          ),
        ],
      ],
    );
  }
}

/// Two letters for a language — «EN», «FR», «فا» — on a colour of its own,
/// the same colour for the same language everywhere.
class WordsLanguageBadge extends StatelessWidget {
  const WordsLanguageBadge({super.key, required this.language});

  final String language;

  static const _hues = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = language.trim();
    final letters = trimmed.isEmpty
        ? '·'
        : trimmed.characters.take(2).toString().toUpperCase();
    final hue = trimmed.isEmpty
        ? Theme.of(context).colorScheme.outline
        : _hues[trimmed.toLowerCase().codeUnits.fold(0, (a, b) => a + b) %
              _hues.length];
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      child: Text(
        letters,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: hue, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The ladder a word climbs — 1, 3, 7, 14, 30 and 60 days — with the rung it
/// stands on lit and the ones below it filled.
class WordsRungs extends StatelessWidget {
  const WordsRungs({super.key, required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final at = card.isNew ? -1 : card.step.clamp(0, wordsLadder.length - 1);
    final color = wordsStageColor(wordsStageOf(card));
    return Row(
      key: const ValueKey('words-card-rungs'),
      children: [
        for (var i = 0; i < wordsLadder.length; i++) ...[
          if (i > 0) const SizedBox(width: NexSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= at ? color : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(NexRadius.pill),
                    border: i == at
                        ? Border.all(color: scheme.onSurface, width: 1.2)
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nexDigits('${wordsLadder[i]}', persian: persian),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: i == at ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: i == at ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
