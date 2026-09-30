part of '../commitments_sheet.dart';

/// A heading over one run of the list.
///
/// Overdue takes the danger colour and the others do not: it is the only one
/// of the three that is about something having gone wrong.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: urgent
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        textDirection: nexDirectionOf(label),
      ),
    );
  }
}

/// Nothing here yet — said as an invitation rather than as a state.
class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.event_repeat_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: NexSpacing.sm),
          // Two lines in the string: what this is, then three examples. The
          // examples are the part that does the work — "recurring item" is
          // a category nobody thinks in, and "the rent" is not.
          Text(
            l10n.commitmentsEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
            textDirection: nexDirectionOf(l10n.commitmentsEmpty),
          ),
        ],
      ),
    );
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({
    required this.commitment,
    required this.onMet,
    required this.onEdit,
    required this.onDelete,
    required this.onActions,
  });

  final NexCommitment commitment;
  final VoidCallback onMet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final overdue = commitment.isOverdue(now);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: nexLabel(context, 'More actions', 'بیشتر'),
                onPressed: onActions,
                icon: const Icon(Icons.more_horiz),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            commitment.title,
                            style: theme.textTheme.bodyLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // It carries a receipt, a note or a card.
                        if (RecurringAttachments.noteIdsOf(
                              commitment.details,
                            ).isNotEmpty ||
                            RecurringAttachments.vaultCardOf(
                                  commitment.details,
                                ) !=
                                null) ...[
                          const SizedBox(width: NexSpacing.xs),
                          Icon(
                            Icons.attach_file,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nexCommitmentSubtitle(l10n, commitment, now),
                      style: theme.textTheme.bodySmall?.copyWith(
                        // Overdue is the one state worth colouring. Everything
                        // else on this screen is simply a date.
                        color: overdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commitmentMarkMet,
                onPressed: onMet,
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: l10n.delete,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
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
