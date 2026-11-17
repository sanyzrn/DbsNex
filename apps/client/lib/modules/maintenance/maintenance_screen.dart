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

part 'maintenance_screen_cards.dart';

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
      floatingActionButton:
          controller.loading ||
              controller.readFailed ||
              controller.assets.isEmpty
          ? null
          : FloatingActionButton.extended(
              // No hero: a page's button never flies into another's (2.8.2).
              heroTag: null,
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
                        key: const ValueKey('maintenance-add-asset'),
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
                    NexModuleHero(
                      key: const ValueKey('maintenance-hero'),
                      moduleId: 'maintenance',
                      icon: Icons.handyman_outlined,
                      eyebrow: s(context, 'heroEyebrow'),
                      headline: (groups[AssetGroup.dueNow]?.length ?? 0) > 0
                          ? s(context, 'heroDue', {
                              'count': groups[AssetGroup.dueNow]!.length,
                            })
                          : s(context, 'heroAllGood'),
                      chips: [
                        if ((groups[AssetGroup.comingUp]?.length ?? 0) > 0)
                          s(context, 'heroComing', {
                            'count': groups[AssetGroup.comingUp]!.length,
                          }),
                        s(context, 'heroAssets', {
                          'count': controller.assets.length,
                        }),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.md),
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
