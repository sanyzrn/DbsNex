import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// The name of a stage of the cycle, as the page says it.
String cycleStageLabel(AppLocalizations l10n, CycleStage stage) =>
    switch (stage) {
      CycleStage.period => l10n.cycleStagePeriod,
      CycleStage.follicular => l10n.cycleStageFollicular,
      CycleStage.fertile => l10n.cycleStageFertile,
      CycleStage.luteal => l10n.cycleStageLuteal,
    };

/// The colour a stage is drawn in: rose for the period, teal for the fertile
/// window, and the space's mauve for the days between.
Color cycleStageColor(CycleStage stage, Brightness brightness) =>
    switch (stage) {
      CycleStage.period => cyclePeriodColor(brightness),
      CycleStage.fertile => cycleFertileColor(brightness),
      CycleStage.follicular || CycleStage.luteal => cycleMauve(brightness),
    };

IconData cycleStageIcon(CycleStage stage) => switch (stage) {
  CycleStage.period => Icons.water_drop_outlined,
  CycleStage.follicular => Icons.eco_outlined,
  CycleStage.fertile => Icons.spa_outlined,
  CycleStage.luteal => Icons.nightlight_outlined,
};

/// A few words for the day, from where the cycle is: gentle, practical, and
/// never advice a doctor would give. A different one each day, so the card is
/// worth a glance rather than learned by heart.
String cycleTip(AppLocalizations l10n, CycleStage stage, CycleDate today) {
  final tips = switch (stage) {
    CycleStage.period => [
      l10n.cycleTipPeriod1,
      l10n.cycleTipPeriod2,
      l10n.cycleTipPeriod3,
      l10n.cycleTipPeriod4,
    ],
    CycleStage.follicular => [
      l10n.cycleTipFollicular1,
      l10n.cycleTipFollicular2,
      l10n.cycleTipFollicular3,
      l10n.cycleTipFollicular4,
    ],
    CycleStage.fertile => [
      l10n.cycleTipFertile1,
      l10n.cycleTipFertile2,
      l10n.cycleTipFertile3,
      l10n.cycleTipFertile4,
    ],
    CycleStage.luteal => [
      l10n.cycleTipLuteal1,
      l10n.cycleTipLuteal2,
      l10n.cycleTipLuteal3,
      l10n.cycleTipLuteal4,
    ],
  };
  // Days since a fixed day, so the tip changes at midnight and not on every
  // visit.
  final index = today.daysSince(const CycleDate(2000, 1, 1));
  return tips[index % tips.length];
}

/// "For today": the stage the cycle is in and a word for it.
class CycleTipCard extends StatelessWidget {
  const CycleTipCard({super.key, required this.stage, required this.today});

  final CycleStage stage;
  final CycleDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = cycleStageColor(stage, theme.brightness);
    return CycleCard(
      key: const ValueKey('cycle-tip'),
      tint: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
            child: Icon(cycleStageIcon(stage), size: 22, color: color),
          ),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.cycleTipTitle} · ${cycleStageLabel(l10n, stage)}',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  cycleTip(l10n, stage, today),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's mood in one tap — the thing most often logged, without opening
/// the day.
class CycleQuickMood extends StatelessWidget {
  const CycleQuickMood({super.key, required this.mood, required this.onPick});

  final CycleMood? mood;

  /// The mood picked, or null when the one already picked is tapped again.
  final ValueChanged<CycleMood?> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rose = cyclePeriodColor(theme.brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.cycleQuickMood,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final value in CycleMood.values)
              IconButton(
                key: ValueKey('cycle-quick-mood-${value.name}'),
                tooltip: cycleMoodLabel(l10n, value),
                isSelected: mood == value,
                onPressed: () => onPick(mood == value ? null : value),
                style: IconButton.styleFrom(
                  backgroundColor: mood == value
                      ? rose.withValues(alpha: 0.18)
                      : Colors.transparent,
                ),
                icon: Icon(
                  cycleMoodIcon(value),
                  color: mood == value
                      ? rose
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Asked when a period has stayed open longer than they usually last: most
/// often the end was simply not logged, and the page should not go on
/// saying "period, day 12".
class CycleEndCheck extends StatelessWidget {
  const CycleEndCheck({
    super.key,
    required this.days,
    required this.onEnded,
    required this.onStill,
  });

  final int days;
  final VoidCallback onEnded;
  final VoidCallback onStill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rose = cyclePeriodColor(theme.brightness);
    return CycleCard(
      key: const ValueKey('cycle-end-check'),
      tint: rose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.help_outline, color: rose),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  l10n.cycleEndCheck(cycleDigits(context, days)),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: NexSpacing.sm,
            children: [
              TextButton(onPressed: onStill, child: Text(l10n.cycleEndCheckNo)),
              FilledButton.tonal(
                onPressed: onEnded,
                child: Text(l10n.cycleEndCheckYes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
