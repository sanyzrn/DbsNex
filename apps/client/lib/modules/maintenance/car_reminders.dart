import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
import 'models.dart';
import 'strings.dart';

/// The car's insurance and inspection alarms, planned from what the asset
/// says (2.8.4): its dates, each lead time and whether the person turned
/// that reminder on. Planned when a date or a lead time changes, and when
/// Nex starts or returns (the module's `keepUp`) — so a renewed insurance
/// moves its alarm instead of leaving one on the old date, an archived car
/// goes quiet, and an alarm that has rung is not set again.
class CarReminders {
  const CarReminders._();

  static const items = ['insurance', 'inspection'];

  static String key(String item, String assetId) => '$item:$assetId';

  static bool on(MaintenanceAsset asset, String item) =>
      item == 'insurance' ? asset.insuranceRemind : asset.inspectionRemind;

  static DateTime? date(MaintenanceAsset asset, String item) =>
      item == 'insurance'
      ? asset.insuranceExpiresAt
      : asset.inspectionExpiresAt;

  static int leadDays(MaintenanceAsset asset, String item) =>
      item == 'insurance' ? asset.insuranceLeadDays : asset.inspectionLeadDays;

  /// Every car, as the store has them now.
  static Future<bool> planAll(
    NexModuleStore store,
    AppLocalizations l10n,
  ) async {
    final assets = [
      for (final r in await store.list('asset'))
        MaintenanceAsset.fromBody(r.id, r.body),
    ];
    return plan(store, assets, l10n);
  }

  /// One car, read again from the store so the plan follows what was saved.
  static Future<bool> planOne(
    NexModuleStore store,
    String assetId,
    AppLocalizations l10n,
  ) async {
    final body = await store.get('asset', assetId);
    if (body == null) return true;
    return plan(store, [MaintenanceAsset.fromBody(assetId, body)], l10n);
  }

  /// False when an alarm that should be set could not be (reminders off for
  /// the module, or no permission).
  static Future<bool> plan(
    NexModuleStore store,
    Iterable<MaintenanceAsset> assets,
    AppLocalizations l10n, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final persian = l10n.localeName.startsWith('fa');
    var ok = true;
    final have = {for (final r in await store.list('__reminder')) r.id: r.body};
    for (final asset in assets) {
      if (asset.type != 'car') continue;
      for (final item in items) {
        final day = date(asset, item);
        final lead = leadDays(asset, item);
        final k = key(item, asset.id);
        if (on(asset, item) &&
            asset.valid &&
            !asset.archived &&
            day != null &&
            CarLogic.reminderFits(day, lead, at)) {
          final ring = CarLogic.reminderAt(day, lead);
          final text = maintenanceStrings.text(l10n, 'carReminderBody', {
            'item': maintenanceStrings.text(l10n, '${item}Label'),
            'car': asset.nickname,
            'date': nexReadableDate(
              day,
              solar: store.solarCalendar,
              persian: persian,
            ),
          });
          final held = have[k];
          // Already set for this moment with these words: nothing to do.
          if (held != null &&
              held['at'] == ring.toUtc().toIso8601String() &&
              held['body'] == text) {
            continue;
          }
          ok &= await store.setReminder(
            k,
            sourceKind: 'asset',
            sourceId: asset.id,
            at: ring,
            title: l10n.cycleNotifyTitle,
            body: text,
          );
        } else if (have.containsKey(k)) {
          // Off, archived, no date, or its moment has gone: no alarm ahead.
          // A notice already in the shade stays.
          await store.withdrawReminder(k);
        }
      }
    }
    return ok;
  }
}
