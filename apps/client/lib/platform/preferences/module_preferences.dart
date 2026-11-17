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

  /// The order added modules are listed in, on Tools and on Modules
  /// (2.8.3), by id. A module missing from it follows, in the app's order.
  List<String> get moduleOrder =>
      _prefs.getStringList('modules.order') ?? const [];
  Future<void> setModuleOrder(List<String> ids) async {
    await _prefs.setStringList('modules.order', [...ids]);
    notifyListeners();
  }

  /// Modules still to come that this person said they want (2.8.3): marked
  /// on their cards, and offered to the developer as an idea.
  Set<String> get wantedModules =>
      (_prefs.getStringList('modules.wanted') ?? const []).toSet();
  Future<void> setModuleWanted(String id, bool wanted) async {
    final all = wantedModules;
    wanted ? all.add(id) : all.remove(id);
    await _prefs.setStringList('modules.wanted', all.toList()..sort());
    notifyListeners();
  }

  /// Pause (2.4.0): the breathing mode last chosen, and whether a session
  /// plays its sound and its haptics. Both on until turned off.
  String get pauseMode => _prefs.getString('module.pause.mode') ?? 'calm';
  Future<void> setPauseMode(String mode) =>
      _setBoundedText('module.pause.mode', mode, 16);
  bool get pauseSound => _prefs.getBool('module.pause.sound') ?? true;
  Future<void> setPauseSound(bool on) => _setBool('module.pause.sound', on);
  bool get pauseHaptics => _prefs.getBool('module.pause.haptics') ?? true;
  Future<void> setPauseHaptics(bool on) => _setBool('module.pause.haptics', on);
}
