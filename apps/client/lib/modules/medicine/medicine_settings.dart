import 'package:nex_client/modules/module_api.dart';

import 'medicine_models.dart';

/// The cabinet's one preference: whether its screen should stay out of
/// screenshots and the app switcher. Names, times and stock are health
/// details, so the offer is made once, in the screen's menu, and off by
/// default — a person who wants screenshots keeps them.
class MedicineSettings {
  const MedicineSettings._();

  static const _id = 'settings';

  static Future<bool> secure(NexModuleStore store) async {
    try {
      final body = await store.get(MedicineModels.settings, _id);
      return body?['secure'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSecure(NexModuleStore store, bool on) async {
    final raw = await store.get(MedicineModels.settings, _id) ?? const {};
    await store.put(MedicineModels.settings, _id, {
      ...raw,
      'v': 1,
      'secure': on,
    });
  }
}
