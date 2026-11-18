import 'package:nex_client/modules/module_api.dart';

import 'medicine_models.dart';
import 'medicine_shared.dart';
import 'medicine_strings.dart';

/// The pinned tile and quick view of the medicine cabinet (2.8.5): today's
/// doses taken out of those due and the next one's time on the tile, never
/// a medicine's name; the names and times in the quick view.
Future<ModuleGlance?> medicineGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      medicineStrings.text(l10n, key, args);
  final medicines = await store.list(MedicineModels.medicine);
  if (medicines.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final today = DateTime(now.year, now.month, now.day);
  final shared = MedicineShared(
    medicines: medicines,
    doses: await store.list(MedicineModels.dose),
    boxes: await store.list(MedicineModels.box),
  );
  final doses = shared
      .duesBetween(today, today.add(const Duration(hours: 23, minutes: 59)))
      .where((d) => d.kind == 'dose')
      .toList();
  final expiring = shared
      .duesBetween(today, today.add(const Duration(days: 30)))
      .where((d) => d.kind == 'expiry')
      .toList();
  final taken = doses.where((d) => d.done).length;
  final next = doses.where((d) => !d.done && !d.at.isBefore(now)).firstOrNull;
  String clock(DateTime at) => nexDigits(
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
    persian: l10n.localeName.startsWith('fa'),
  );
  return ModuleGlance(
    headline: doses.isEmpty
        ? t('glanceNoDoses')
        : t('glanceDoses', {'done': taken, 'total': doses.length}),
    detail: next == null
        ? (expiring.isEmpty
              ? null
              : t('glanceExpiring', {'n': expiring.length}))
        : t('glanceNext', {'time': clock(next.at)}),
    progress: doses.isEmpty ? null : taken / doses.length,
    facts: [
      for (final dose in doses)
        ModuleGlanceFact(
          '${clock(dose.at)}  ${dose.title}',
          dose.done ? t('glanceTaken') : t('glanceWaiting'),
          strong: identical(dose, next),
        ),
      for (final box in expiring)
        ModuleGlanceFact(
          t('glanceBoxOf', {'name': box.title}),
          nexDueWhen(l10n, box.at, today),
        ),
    ],
  );
}
