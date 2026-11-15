part of 'warranty_detail.dart';

/// Where the cover stands, in one calm card: the days left or since it
/// ended, and the end date on the person's own calendar. The kind of cover
/// has its own row below, so it is not repeated here. Nothing is scheduled
/// or assumed.
class _WarrantyStatusCard extends StatelessWidget {
  const _WarrantyStatusCard({required this.end});

  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final status = end == null ? null : WarrantyLogic.statusOf(end!, now);
    final hue = end == null
        ? NexHue.slate
        : status!.expired
        ? NexHue.slate
        : status.expiring
        ? NexHue.amber
        : NexHue.teal;
    final accent = hue.of(theme.brightness);
    final headline = end == null
        ? strings(context, 'unknownDate')
        : WarrantyFields.remaining(context, end!, now);
    // "Ended 12 days ago" already says it ended; repeating the word under
    // it only made the card read twice.
    final dayLabel = end == null
        ? null
        : WarrantyFields.dayLabel(context, end!);
    final sub = dayLabel == null
        ? null
        : status!.expired
        ? dayLabel
        : strings(context, 'statusOn', {'date': dayLabel});
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NexRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  end == null
                      ? Icons.help_outline
                      : status!.expired
                      ? Icons.event_busy_outlined
                      : status.expiring
                      ? Icons.schedule_outlined
                      : Icons.verified_outlined,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: NexSpacing.sm),
                Flexible(
                  child: Text(
                    strings(context, 'heroEyebrow'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            Text(
              headline,
              key: const ValueKey('warranty-status-headline'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (sub != null)
              Text(
                sub,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
