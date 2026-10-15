part of '../nex_preferences.dart';

/// Which modules are part of the app — see `docs/17-modules.md`.
///
/// One key per module, `module.<id>.on`, off until added except the owner's
/// 2.0.1 preview set. Explicit choices always win. Cycle predates this
/// and keeps its own key ([_CyclePreferences.cycleEnabled]) so nobody's Cycle
/// switches off on update.
mixin _ModulePreferences on _PreferencesStore {
  bool isModuleOn(String id) =>
      _prefs.getBool('module.$id.on') ?? nexPreviewModuleIds.contains(id);
  Future<void> setModuleOn(String id, bool on) => _setBool('module.$id.on', on);
}
