part of '../nex_preferences.dart';

/// «Cycle»: what was given at the start, and which reminders are on.
///
/// The periods and daily logs themselves are in the library database, so a
/// backup carries them; these are only how this phone should behave.
mixin _CyclePreferences on _PreferencesStore {
  /// Whether «Cycle» is part of the app at all. On by default; off, its
  /// tile, its reminders and everything it does at launch are gone, and its
  /// data is kept or deleted as the person chose when turning it off.
  bool get cycleEnabled => _prefs.getBool('cycle.enabled') ?? true;
  Future<void> setCycleEnabled(bool value) => _setBool('cycle.enabled', value);

  /// Whether the three opening questions have been answered or skipped.
  bool get cycleSetUp => _prefs.getBool('cycle.set_up') ?? false;
  Future<void> setCycleSetUp(bool value) => _setBool('cycle.set_up', value);

  /// The cycle and period lengths given at the start, used until enough
  /// has been logged to learn them.
  int get cycleTypicalLength =>
      (_prefs.getInt('cycle.typical_cycle') ?? 28).clamp(15, 60);
  int get cycleTypicalPeriod =>
      (_prefs.getInt('cycle.typical_period') ?? 5).clamp(1, 15);
  Future<void> setCycleTypical({int? cycle, int? period}) async {
    if (cycle != null) await _prefs.setInt('cycle.typical_cycle', cycle);
    if (period != null) await _prefs.setInt('cycle.typical_period', period);
    notifyListeners();
  }

  /// What «Cycle» is for right now — see [CycleMode].
  CycleMode get cycleMode => CycleMode.fromWire(_prefs.getString('cycle.mode'));
  Future<void> setCycleMode(CycleMode mode) async {
    await _prefs.setString('cycle.mode', mode.name);
    notifyListeners();
  }

  /// In [CycleMode.pregnant]: the first day of the last period, from which
  /// the weeks are counted.
  CycleDate? get cyclePregnancyStart {
    final text = _prefs.getString('cycle.pregnancy_start');
    return text == null ? null : CycleDate.parse(text);
  }

  Future<void> setCyclePregnancyStart(CycleDate? day) async {
    if (day == null) {
      await _prefs.remove('cycle.pregnancy_start');
    } else {
      await _prefs.setString('cycle.pregnancy_start', '$day');
    }
    notifyListeners();
  }

  /// Two days before the next period is expected.
  bool get cycleRemindSoon => _prefs.getBool('cycle.remind_soon') ?? true;
  Future<void> setCycleRemindSoon(bool value) =>
      _setBool('cycle.remind_soon', value);

  /// Each evening of a period, to note the day.
  bool get cycleRemindLog => _prefs.getBool('cycle.remind_log') ?? false;
  Future<void> setCycleRemindLog(bool value) =>
      _setBool('cycle.remind_log', value);

  /// A daily pill, at [cyclePillMinutes] after midnight.
  bool get cycleRemindPill => _prefs.getBool('cycle.remind_pill') ?? false;
  Future<void> setCycleRemindPill(bool value) =>
      _setBool('cycle.remind_pill', value);
  int get cyclePillMinutes =>
      (_prefs.getInt('cycle.pill_minutes') ?? 21 * 60).clamp(0, 24 * 60 - 1);
  Future<void> setCyclePillMinutes(int minutes) async {
    await _prefs.setInt('cycle.pill_minutes', minutes);
    notifyListeners();
  }

  /// Forgets everything above — part of "delete all cycle data".
  Future<void> resetCycle() async {
    for (final key in [
      'cycle.set_up',
      'cycle.typical_cycle',
      'cycle.typical_period',
      'cycle.remind_soon',
      'cycle.remind_log',
      'cycle.remind_pill',
      'cycle.pill_minutes',
      'cycle.mode',
      'cycle.pregnancy_start',
    ]) {
      await _prefs.remove(key);
    }
    notifyListeners();
  }
}
