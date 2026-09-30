part of '../commitments_sheet.dart';

/// A heading over one run of the list, with how many are in it.
///
/// Overdue takes the danger colour and the others do not: it is the only one
/// of the three that is about something having gone wrong.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.label,
    required this.urgent,
    required this.count,
  });

  final String label;
  final bool urgent;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = urgent
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            textDirection: nexDirectionOf(label),
          ),
          const SizedBox(width: NexSpacing.sm),
          Text(
            nexDigits(
              '$count',
              persian: Localizations.localeOf(context).languageCode == 'fa',
            ),
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Three numbers at the top of the page — what has slipped, what is due
/// today, what is due this week — each of them also the way to see just
/// those.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.view,
    required this.counts,
    required this.persian,
    required this.onView,
  });

  final String view;
  final Map<String, int> counts;
  final bool persian;
  final ValueChanged<String> onView;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (id, en, fa, icon, urgent) in [
          ('overdue', 'Overdue', 'عقب‌افتاده', Icons.error_outline, true),
          ('today', 'Today', 'امروز', Icons.today_outlined, false),
          ('week', 'Next 7 days', '۷ روز آینده', Icons.date_range, false),
        ]) ...[
          if (id != 'overdue') const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: _Stat(
              key: ValueKey('recurring-stat-$id'),
              icon: icon,
              label: nexLabel(context, en, fa),
              value: nexDigits('${counts[id] ?? 0}', persian: persian),
              selected: view == id,
              color: urgent && (counts[id] ?? 0) > 0
                  ? scheme.error
                  : scheme.primary,
              onTap: () => onView(id),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                color.withValues(alpha: 0.14),
                scheme.surfaceContainerLowest,
              )
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.sm + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the paying ones add up to over the next thirty days.
class _Payments extends StatelessWidget {
  const _Payments({required this.totals, required this.persian});

  final Map<String, int> totals;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: scheme.onPrimaryContainer),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nexLabel(
                    context,
                    'Payments in the next 30 days',
                    'پرداخت‌های ۳۰ روز آینده',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                for (final e in totals.entries)
                  Text(
                    nexDigits(
                      '${(e.value / 100).toStringAsFixed(2)} ${e.key}',
                      persian: persian,
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
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

/// Nothing here yet — said as an invitation rather than as a state, with
/// the one thing to do about it.
class _Empty extends StatelessWidget {
  const _Empty({required this.l10n, required this.onAdd});

  final AppLocalizations l10n;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xl),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(NexSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_repeat_outlined,
              size: 48,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: NexSpacing.lg),
          // Two lines in the string: what this is, then three examples. The
          // examples are the part that does the work — "recurring item" is
          // a category nobody thinks in, and "the rent" is not.
          Text(
            l10n.commitmentsEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            textDirection: nexDirectionOf(l10n.commitmentsEmpty),
          ),
          const SizedBox(height: NexSpacing.lg),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.commitmentAdd),
          ),
        ],
      ),
    );
  }
}

IconData _cadenceIcon(NexCadence cadence) => switch (cadence) {
  NexCadence.hours => Icons.schedule,
  NexCadence.days => Icons.wb_sunny_outlined,
  NexCadence.weeks => Icons.view_week_outlined,
  NexCadence.months => Icons.calendar_month_outlined,
  NexCadence.years => Icons.cake_outlined,
};

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({
    required this.commitment,
    required this.onMet,
    required this.onEdit,
    required this.onActions,
  });

  final NexCommitment commitment;
  final VoidCallback onMet;
  final VoidCallback onEdit;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final overdue = commitment.isOverdue(now);
    final accent = overdue
        ? scheme.error
        : commitment.paused
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final attached =
        RecurringAttachments.noteIdsOf(commitment.details).isNotEmpty ||
        RecurringAttachments.vaultCardOf(commitment.details) != null;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side: BorderSide(
          color: overdue
              ? scheme.error.withValues(alpha: 0.6)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.xs,
            NexSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(NexRadius.md),
                ),
                child: Icon(_cadenceIcon(commitment.cadence), color: accent),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            commitment.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // It carries a receipt, a note or a card.
                        if (attached) ...[
                          const SizedBox(width: NexSpacing.xs),
                          Icon(
                            Icons.attach_file,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nexCommitmentSubtitle(l10n, commitment, now),
                      style: theme.textTheme.bodySmall?.copyWith(
                        // Overdue is the one state worth colouring.
                        color: overdue ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commitmentMarkMet,
                onPressed: onMet,
                color: accent,
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: nexLabel(context, 'More actions', 'بیشتر'),
                onPressed: onActions,
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "every month · due in 2 days", or "every 2h · 3 of 7 today".
///
/// Top-level rather than a method, so the row and the editor's preview say the
/// same sentence about the same commitment without one of them drifting.
String nexCommitmentSubtitle(
  AppLocalizations l10n,
  NexCommitment commitment,
  DateTime now,
) {
  final cadence = nexCadenceLabel(l10n, commitment.cadence, commitment.every);
  if (commitment.paused) return '$cadence · ${l10n.commitmentPaused}';
  final tally = commitment.timesPerDay;
  if (tally != null) {
    return '$cadence · ${l10n.commitmentTally(commitment.metOn(now), tally)}';
  }
  final away = commitment.dueAt.difference(now);
  final when = away.isNegative
      ? l10n.commitmentOverdue(nexRelativeSpan(l10n, -away))
      : l10n.commitmentDueIn(nexRelativeSpan(l10n, away));
  return '$cadence · $when';
}

String nexCadenceLabel(AppLocalizations l10n, NexCadence cadence, int every) =>
    switch (cadence) {
      NexCadence.hours => l10n.cadenceHours(every),
      NexCadence.days => l10n.cadenceDays(every),
      NexCadence.weeks => l10n.cadenceWeeks(every),
      NexCadence.months => l10n.cadenceMonths(every),
      NexCadence.years => l10n.cadenceYears(every),
    };
