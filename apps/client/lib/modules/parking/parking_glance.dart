import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_strings.dart';

/// The pinned tile and quick view of Parking (2.8.5): where the car is and
/// how long is left on the tile; every clue in the quick view.
Future<ModuleGlance?> parkingGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      parkingStrings.text(l10n, key, args);
  final active =
      (await store.list(ParkingModels.session))
          .map((r) => r.body)
          .where(ParkingLogic.isActive)
          .toList()
        ..sort((a, b) {
          final x = ParkingModels.readDate(a, 'startedAt');
          final y = ParkingModels.readDate(b, 'startedAt');
          if (x == null || y == null) return 0;
          return y.compareTo(x);
        });
  if (active.isEmpty) return ModuleGlance(headline: t('glanceNone'));
  final session = active.first;
  String read(String key) => ParkingModels.readString(session, key).trim();
  final where = [read('place'), read('floor'), read('spot')]
      .where((s) => s.isNotEmpty)
      .join(l10n.localeName.startsWith('fa') ? '، ' : ' · ');
  final expires = ParkingModels.readDate(session, 'expiresAt');
  final expiry = ParkingLogic.expiryOf(session, now);
  final parked = ParkingLogic.split(ParkingLogic.elapsedOf(session, now));
  String span(({int days, int hours, int minutes}) s) => s.days > 0
      ? t('glanceDaysHours', {'d': s.days, 'h': s.hours})
      : s.hours > 0
      ? t('glanceHoursMinutes', {'h': s.hours, 'm': s.minutes})
      : t('glanceMinutes', {'m': s.minutes});
  final left = expires == null
      ? null
      : expiry.over
      ? t('glanceOver', {
          'time': span(ParkingLogic.split(Duration(minutes: expiry.minutes))),
        })
      : t('glanceLeft', {
          'time': span(ParkingLogic.split(Duration(minutes: expiry.minutes))),
        });
  return ModuleGlance(
    headline: where.isEmpty ? t('glanceParked') : where,
    detail: left ?? t('glanceFor', {'time': span(parked)}),
    facts: [
      if (read('vehicle').isNotEmpty)
        ModuleGlanceFact(t('glanceVehicle'), read('vehicle')),
      if (read('place').isNotEmpty)
        ModuleGlanceFact(t('glancePlace'), read('place'), strong: true),
      if (read('floor').isNotEmpty)
        ModuleGlanceFact(t('glanceFloor'), read('floor')),
      if (read('spot').isNotEmpty)
        ModuleGlanceFact(t('glanceSpot'), read('spot')),
      if (read('landmark').isNotEmpty)
        ModuleGlanceFact(t('glanceLandmark'), read('landmark')),
      ModuleGlanceFact(t('glanceParkedFor'), span(parked)),
      if (left != null) ModuleGlanceFact(t('glancePaid'), left),
      if (active.length > 1)
        ModuleGlanceFact(
          t('glanceOthers'),
          nexDigits(
            '${active.length - 1}',
            persian: l10n.localeName.startsWith('fa'),
          ),
        ),
    ],
  );
}
