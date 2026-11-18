import 'package:nex_client/modules/module_api.dart';

import 'maintenance_shared.dart';
import 'strings.dart';

/// The pinned tile and quick view of Maintenance (2.8.5): the next thing
/// due and when on the tile; the next few — services, insurance,
/// inspection — in the quick view.
Future<ModuleGlance?> maintenanceGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      maintenanceStrings.text(l10n, key, args);
  final records = {
    for (final kind in const ['asset', 'event', 'rule', 'reading'])
      kind: await store.list(kind),
  };
  final assets = records['asset']!;
  if (assets.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final today = DateTime(now.year, now.month, now.day);
  final dues = MaintenanceShared.fromRecords(records)
      .duesBetween(
        today.subtract(const Duration(days: 365)),
        today.add(const Duration(days: 365)),
      )
      .where((d) => !d.done)
      .toList();
  String title(ModuleDue d) => switch (d.kind) {
    'insurance-expiry' => '${d.title}: ${t('insuranceLabel')}',
    'inspection-expiry' => '${d.title}: ${t('inspectionLabel')}',
    _ => d.title,
  };
  final next = dues.firstOrNull;
  return ModuleGlance(
    headline: next == null ? t('glanceAllClear') : title(next),
    detail: next == null
        ? t('glanceAssets', {'n': assets.length})
        : nexDueWhen(l10n, next.at, today),
    facts: [
      for (final due in dues.take(6))
        ModuleGlanceFact(
          title(due),
          nexDueWhen(l10n, due.at, today),
          strong: identical(due, next),
        ),
      ModuleGlanceFact(
        t('glanceAssetsLabel'),
        nexDigits(
          '${assets.length}',
          persian: l10n.localeName.startsWith('fa'),
        ),
      ),
    ],
  );
}
