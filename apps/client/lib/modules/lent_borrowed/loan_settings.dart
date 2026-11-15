import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';

/// The module's own small preferences, kept as one record so they travel in
/// backups with everything else and need no platform preference the module
/// kit keeps out.
///
/// Today it holds one choice: how Iranians amounts are said (toman or rial).
/// It is read defensively — a missing or malformed record means the default,
/// never an error on a screen.
class LoanSettings {
  const LoanSettings({this.irrUnit = IrrUnit.toman});

  static const kind = 'settings';
  static const id = 'settings';

  final IrrUnit irrUnit;

  Map<String, Object?> toJson() => {'v': 1, 'irrUnit': irrUnit.key};
}

/// Reads the saved choice; toman until the person says otherwise, because
/// that is what people in Iran actually say.
Future<LoanSettings> readLoanSettings(NexModuleStore store) async {
  try {
    final body = await store.get(LoanSettings.kind, LoanSettings.id);
    if (body == null) return const LoanSettings();
    return LoanSettings(irrUnit: IrrUnit.fromKey(body['irrUnit']));
  } catch (_) {
    // A settings record that cannot be read must not stop the list from
    // opening; the default is the same one a new installation has.
    return const LoanSettings();
  }
}

/// Saves the choice, keeping any field a later version added.
Future<void> saveIrrUnit(NexModuleStore store, IrrUnit unit) async {
  final old = await store.get(LoanSettings.kind, LoanSettings.id) ?? const {};
  await store.put(LoanSettings.kind, LoanSettings.id, {
    ...old,
    ...const LoanSettings().toJson(),
    'irrUnit': unit.key,
  });
}
