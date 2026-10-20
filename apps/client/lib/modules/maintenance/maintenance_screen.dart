import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'asset_editor.dart';
import 'asset_page.dart';
import 'controller.dart';
import 'logic.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The Maintenance home: every asset under its group — due now,
/// coming up, needing information, no schedule, archived — computed
/// when the module is opened, from the latest real services. One
/// primary action: add an asset.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with WidgetsBindingObserver {
  late final MaintenanceController controller = MaintenanceController(
    widget.store,
  );

  /// Captured once per open: the groups are a snapshot of now, not a
  /// ticking clock — recomputed on the next open or write.
  late DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.load());
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) {
      setState(() {
        _openedAt = DateTime.now();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _openedAt = DateTime.now());
      unawaited(controller.load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = maintenanceStrings;
    final standings = <String, List<RuleStanding>>{};
    for (final asset in controller.assets) {
      standings[asset.id] = ruleStandings(
        asset,
        controller.events,
        controller.rules,
        _openedAt,
        readings: controller.readings,
      );
    }
    final groups = <AssetGroup, List<MaintenanceAsset>>{};
    for (final asset in controller.assets) {
      final group = assetGroupOf(
        asset,
        standings[asset.id] ?? [],
        _openedAt,
        incompleteRules: controller.invalidRules.any(
          (r) => r.body['assetId'] == asset.id,
        ),
      );
      groups.putIfAbsent(group, () => []).add(asset);
    }
    final ordered = [
      AssetGroup.dueNow,
      AssetGroup.comingUp,
      AssetGroup.needsInfo,
      AssetGroup.scheduled,
      AssetGroup.noSchedule,
      AssetGroup.archived,
    ];
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'title'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('maintenance-add-asset'),
        onPressed: () =>
            unawaited(showAssetEditor(context, controller: controller)),
        icon: const Icon(Icons.add),
        label: Text(s(context, 'addAsset')),
      ),
      body: SafeArea(
        child: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.readFailed
            ? NexEmptyState(
                icon: Icons.error_outline,
                message: s(context, 'loadFailed'),
                action: TextButton(
                  onPressed: () => unawaited(controller.load()),
                  child: Text(s(context, 'retry')),
                ),
              )
            : ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl * 3,
                ),
                children: [
                  if (controller.assets.isEmpty)
                    NexEmptyState(
                      icon: Icons.handyman_outlined,
                      message: s(context, 'noAssets'),
                      action: FilledButton.icon(
                        onPressed: () => unawaited(
                          showAssetEditor(context, controller: controller),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(s(context, 'addAsset')),
                        // Material's default caps a filled button at 40 px
                        // tall, which a 2× text scale cannot fit into; let it
                        // grow with the words instead of clipping them.
                        style: const ButtonStyle(
                          maximumSize: WidgetStatePropertyAll<Size?>(
                            Size(double.infinity, double.infinity),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      s(context, 'noReminders'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    for (final group in ordered)
                      if (groups[group]?.isNotEmpty == true) ...[
                        _GroupHeading(
                          group: group,
                          count: groups[group]!.length,
                          now: _openedAt,
                        ),
                        for (final asset in groups[group]!)
                          _AssetCard(
                            asset: asset,
                            group: group,
                            standing: standings[asset.id] ?? const [],
                            now: _openedAt,
                            onTap: () => unawaited(
                              Navigator.push(
                                context,
                                NexPageRoute(
                                  builder: (_) => AssetPage(
                                    store: widget.store,
                                    assetId: asset.id,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                  ],
                ],
              ),
      ),
    );
  }
}

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
