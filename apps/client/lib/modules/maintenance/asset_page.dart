import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'asset_editor.dart';
import 'controller.dart';
import 'costs.dart';
import 'event_editor.dart';
import 'logic.dart';
import 'asset_page_actions.dart';
import 'maintenance_common.dart';
import 'maintenance_widgets.dart';
import 'rule_editor.dart';
import 'strings.dart';
import 'units.dart';
import 'reading_widgets.dart';

/// One asset's own page: what it is, what is due, its interval rules,
/// the full service timeline, and the costs the person entered. Every
/// due fact is recomputed from the records on every change.
class AssetPage extends StatefulWidget {
  const AssetPage({super.key, required this.store, required this.assetId});

  final NexModuleStore store;
  final String assetId;

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> with WidgetsBindingObserver {
  late final MaintenanceController controller = MaintenanceController(
    widget.store,
  );
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
    final scheme = theme.colorScheme;
    final s = maintenanceStrings;
    final asset = controller.assetById(widget.assetId);
    if (controller.loading || controller.readFailed || asset == null) {
      return Scaffold(
        appBar: NexAppBar(title: Text(s(context, 'title'))),
        body: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : NexEmptyState(
                icon: Icons.handyman_outlined,
                message: s(
                  context,
                  controller.readFailed ? 'loadFailed' : 'assetGone',
                ),
                action: controller.readFailed
                    ? TextButton(
                        onPressed: () => unawaited(controller.load()),
                        child: Text(s(context, 'retry')),
                      )
                    : null,
              ),
      );
    }
    final standings = ruleStandings(
      asset,
      controller.events,
      controller.rules,
      _openedAt,
      readings: controller.readings,
    );
    final events =
        controller.events.where((e) => e.assetId == asset.id).toList()
          // Deterministic order: same-date services fall back to the
          // record id instead of the sort's accidental order.
          ..sort(compareServices);
    final done =
        events
            .where(
              (e) =>
                  serviceDateKnown(e) &&
                  !dayOf(e.date).isAfter(dayOf(_openedAt)),
            )
            .toList()
          ..sort(compareServices);
    final latest = done.isEmpty ? null : done.first;
    final costTotals = assetCostTotals(events);
    final hue = NexHue.amber.of(theme.brightness);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          asset.nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: s(context, 'editAssetTitle'),
            onPressed: () => unawaited(
              showAssetEditor(context, controller: controller, existing: asset),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          NexPopupMenuButton<String>(
            tooltip: s(context, 'moreActions'),
            onSelected: (action) => unawaited(
              assetPageMenu(
                context,
                action: action,
                controller: controller,
                asset: asset,
                events: events,
                standings: standings,
              ),
            ),
            itemBuilder: (menuContext) => [
              PopupMenuItem(
                value: asset.archived ? 'unarchive' : 'archive',
                child: Text(
                  s(menuContext, asset.archived ? 'unarchive' : 'archive'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(s(menuContext, 'delete')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('maintenance-log-service'),
        onPressed: asset.archived
            ? null
            : () => unawaited(
                showEventEditor(context, controller: controller, asset: asset),
              ),
        icon: const Icon(Icons.add),
        label: Text(s(context, 'logService')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.xl * 3,
          ),
          children: [
            NexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NexIconTile(maintenanceTypeIcon(asset.type), color: hue),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Text(
                          [
                            maintenanceTypeLabel(context, asset.type),
                            if (asset.model?.isNotEmpty == true) asset.model!,
                          ].join(' · '),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  ...assetInfoLines(context, asset),
                ],
              ),
            ),
            if (!asset.archived) ...[
              const SizedBox(height: NexSpacing.md),
              Text(
                s(context, 'reminderNote'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              // Opt-in: an OS alert for this asset's next due service.
              // Wired to the asset record, so the platform cancels it
              // when the asset is deleted or archived — and archived
              // assets offer nothing here.
              NexModuleReminderControl(
                key: const ValueKey('maintenance-reminders'),
                store: widget.store,
                sourceKind: 'asset',
                sourceId: asset.id,
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            if (asset.meterKind != MeterKind.none)
              ReadingPanel(
                controller: controller,
                asset: asset,
                now: _openedAt,
              ),
            const SizedBox(height: NexSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s(context, 'rulesTitle'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: asset.archived
                      ? null
                      : () => unawaited(
                          showRuleEditor(
                            context,
                            controller: controller,
                            asset: asset,
                          ),
                        ),
                  child: Text(s(context, 'newRuleTitle')),
                ),
              ],
            ),
            for (final raw in controller.invalidRules.where(
              (r) => r.body['assetId'] == asset.id,
            ))
              InvalidRuleRow(controller: controller, record: raw, asset: asset),
            if (standings.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: NexSpacing.md,
                ),
                child: Text(
                  s(context, 'noRules'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              for (final standing in standings)
                RuleRow(
                  key: ValueKey('maintenance-rule-${standing.rule.id}'),
                  standing: standing,
                  now: _openedAt,
                  onTap: () => unawaited(
                    showRuleEditor(
                      context,
                      controller: controller,
                      asset: asset,
                      existing: standing.rule,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: NexSpacing.xs,
                  bottom: NexSpacing.md,
                ),
                child: Text(
                  s(context, 'earliestNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (latest != null)
              OutlinedButton.icon(
                key: const ValueKey('maintenance-repeat'),
                onPressed: () => unawaited(
                  showEventEditor(
                    context,
                    controller: controller,
                    asset: asset,
                    repeatOf: latest,
                  ),
                ),
                icon: const Icon(Icons.replay_outlined),
                label: Text(s(context, 'repeatLast')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            const SizedBox(height: NexSpacing.md),
            Text(
              s(context, 'serviceHistory'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: NexSpacing.xs),
            if (events.isEmpty)
              Text(
                s(context, 'noEvents'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (final event in events)
                EventRow(
                  key: ValueKey('maintenance-event-${event.id}'),
                  event: event,
                  now: _openedAt,
                  onTap: () => unawaited(
                    showEventEditor(
                      context,
                      controller: controller,
                      asset: asset,
                      existing: event,
                    ),
                  ),
                ),
            if (costTotals.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              NexPanel(
                title: s(context, 'costSummary'),
                icon: Icons.payments_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in costTotals.entries)
                      Text(
                        '${formatCostNumber(entry.value, costExponentOf(entry.key), persian: NexModuleStrings.persian(context))} ${entry.key}',
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodyLarge,
                      ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      s(context, 'costSummaryNote'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
