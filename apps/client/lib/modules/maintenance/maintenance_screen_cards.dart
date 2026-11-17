part of 'maintenance_screen.dart';

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.group,
    required this.count,
    required this.now,
  });

  final AssetGroup group;
  final int count;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = maintenanceStrings;
    final hue = NexHue.amber.of(theme.brightness);
    final title = assetGroupTitle(context, group);
    final note = switch (group) {
      AssetGroup.dueNow => s(context, 'groupDueNowNote'),
      AssetGroup.comingUp => s(context, 'groupComingUpNote', {
        'n': comingUpDays,
      }),
      AssetGroup.needsInfo => s(context, 'groupNeedsInfoNote'),
      AssetGroup.scheduled => s(context, 'groupScheduledNote'),
      AssetGroup.noSchedule => s(context, 'groupNoScheduleNote'),
      AssetGroup.archived => s(context, 'unarchive'),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NexSpacing.xs,
        bottom: NexSpacing.sm,
      ),
      child: Row(
        children: [
          if (group == AssetGroup.dueNow)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
              child: Icon(Icons.error_outline, size: 16, color: hue),
            ),
          Expanded(
            child: Text(
              '$title · ${maintenanceDigits(context, count)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: group == AssetGroup.dueNow ? hue : scheme.onSurface,
              ),
            ),
          ),
          Flexible(
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// `12` in the locale's digits.
String maintenanceDigits(BuildContext context, int value) {
  final persian = NexModuleStrings.persian(context);
  return persian ? persianDigits('$value') : '$value';
}

/// The group's name, for the heading and the card's semantics label.
String assetGroupTitle(BuildContext context, AssetGroup group) =>
    switch (group) {
      AssetGroup.dueNow => maintenanceStrings(context, 'groupDueNow'),
      AssetGroup.comingUp => maintenanceStrings(context, 'groupComingUp'),
      AssetGroup.needsInfo => maintenanceStrings(context, 'groupNeedsInfo'),
      AssetGroup.scheduled => maintenanceStrings(context, 'groupScheduled'),
      AssetGroup.noSchedule => maintenanceStrings(context, 'groupNoSchedule'),
      AssetGroup.archived => maintenanceStrings(context, 'groupArchived'),
    };

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.group,
    required this.standing,
    required this.now,
    required this.onTap,
  });

  final MaintenanceAsset asset;
  final AssetGroup group;
  final List<RuleStanding> standing;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = maintenanceStrings;
    final hue = NexHue.amber.of(theme.brightness);
    final typeLabel = s(
      context,
      'type${asset.type[0].toUpperCase()}${asset.type.substring(1)}',
    );
    // The most urgent fact this asset has, as its subtitle.
    String? urgent;
    for (final rule in standing) {
      if (rule.dueNow(now)) {
        urgent = rule.rule.task;
        break;
      }
      if (rule.unknown) {
        urgent ??= rule.rule.hours != null
            ? s(context, 'hoursDueUnknown')
            : s(context, 'distanceDueUnknown');
      }
    }
    urgent ??= standing.isEmpty ? null : standing.first.rule.task;
    return Semantics(
      label: s(context, 'assetSemantics', {
        'name': asset.nickname,
        'type': typeLabel,
        'group': assetGroupTitle(context, group),
      }),
      button: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.sm),
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: Row(
                children: [
                  NexIconTile(_typeIcon(asset.type), color: hue),
                  const SizedBox(width: NexSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          urgent == null ? typeLabel : '$typeLabel · $urgent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: group == AssetGroup.dueNow
                                ? hue
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (asset.archived)
                    Icon(
                      Icons.archive_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    )
                  else
                    Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _typeIcon(String type) => switch (type) {
  'car' => Icons.directions_car_outlined,
  'motorcycle' => Icons.two_wheeler_outlined,
  'ac' => Icons.ac_unit_outlined,
  'boiler' => Icons.hot_tub_outlined,
  'filter' => Icons.water_drop_outlined,
  'appliance' => Icons.home_repair_service_outlined,
  _ => Icons.build_outlined,
};
