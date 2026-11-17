part of 'modules_screen.dart';

/// A module still to come: its glyph, its name with a badge for how near it
/// is, and a line on what it will do. Quieter than an available module's
/// card — no wash of colour, no button — since there is nothing to do with
/// it yet but know it is coming.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.wanted,
    required this.onWant,
  });

  final NexModulePlan plan;

  /// Whether this person marked it as wanted (2.8.3).
  final bool wanted;
  final VoidCallback onWant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = plan.hue.of(theme.brightness);
    final soon = plan.stage == NexModuleStage.soon;
    return Container(
      key: ValueKey('plan-${plan.id}'),
      padding: const EdgeInsets.all(NexSpacing.md - 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
            child: Icon(plan.icon, color: color, size: 22),
          ),
          const SizedBox(width: NexSpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      plan.title(l10n),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: soon
                            ? color.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(NexRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                          vertical: 2,
                        ),
                        child: Text(
                          soon ? l10n.moduleStageSoon : l10n.moduleStagePlanned,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: soon
                                ? nexReadableOn(
                                    color,
                                    scheme.surfaceContainerLow,
                                  )
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  plan.about(l10n),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: ValueKey('plan-${plan.id}-want'),
                    onPressed: onWant,
                    style: TextButton.styleFrom(
                      foregroundColor: wanted ? color : scheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexSpacing.sm,
                      ),
                    ),
                    icon: Icon(
                      wanted ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                    ),
                    label: Text(wanted ? l10n.moduleWanted : l10n.moduleWant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
