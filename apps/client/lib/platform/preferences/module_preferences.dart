part of '../nex_preferences.dart';

/// Which modules are part of the app — see `docs/17-modules.md`.
///
/// One key per module, `module.<id>.on`, off until explicitly added.
/// Cycle predates this
/// and keeps its own key ([_CyclePreferences.cycleEnabled]) so nobody's Cycle
/// switches off on update.
mixin _ModulePreferences on _PreferencesStore {
  bool isModuleOn(String id) => _prefs.getBool('module.$id.on') ?? false;
  Future<void> setModuleOn(String id, bool on) => _setBool('module.$id.on', on);
}
