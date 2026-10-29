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

  /// Pause (2.3.7): the breathing mode last chosen, and whether a session
  /// plays its sound and its haptics. Both on until turned off.
  String get pauseMode => _prefs.getString('module.pause.mode') ?? 'calm';
  Future<void> setPauseMode(String mode) =>
      _setBoundedText('module.pause.mode', mode, 16);
  bool get pauseSound => _prefs.getBool('module.pause.sound') ?? true;
  Future<void> setPauseSound(bool on) => _setBool('module.pause.sound', on);
  bool get pauseHaptics => _prefs.getBool('module.pause.haptics') ?? true;
  Future<void> setPauseHaptics(bool on) => _setBool('module.pause.haptics', on);
}
