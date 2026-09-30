part of '../nex_preferences.dart';

/// The app lock.
mixin _SecurityPreferences on _PreferencesStore {
  bool get appLockEnabled => _prefs.getBool('security.app_lock') ?? false;

  bool get appLockBiometricOnly =>
      _prefs.getBool('security.biometric_only') ?? false;

  AppLockTiming get appLockTiming =>
      AppLockTimingWire.fromWire(_prefs.getString('security.lock_timing'));

  /// How long [AppLockTiming.after] waits, in seconds.
  ///
  /// Seconds rather than minutes because the useful values are short: the
  /// case this exists for is a trip to another app and straight back, not an
  /// afternoon away.
  int get appLockGraceSeconds =>
      _prefs.getInt('security.lock_grace_seconds') ?? 60;

  /// Whether the lock is currently closed, remembered across a process death.
  ///
  /// Without this, "lock only when I ask" would come undone by Android
  /// stopping the app: the flag lives in memory, the process goes, and the
  /// library opens unlocked next time. It is set when the lock closes and
  /// cleared when it opens, so the answer survives whatever the OS does in
  /// between.
  bool get appLockClosed => _prefs.getBool('security.lock_closed') ?? false;

  /// When the app last went to the background, for [AppLockTiming.after].
  ///
  /// Also persisted, and for the same reason: the grace period has to be
  /// measured against wall-clock time, not against how long this particular
  /// process happened to survive.
  DateTime? get appLockLeftAt {
    final value = _prefs.getInt('security.lock_left_at');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> setAppLockEnabled(bool value) async {
    await _prefs.setBool('security.app_lock', value);
    if (!value) await _prefs.setBool('security.biometric_only', false);
    notifyListeners();
  }

  Future<void> setAppLockTiming(AppLockTiming value) async {
    await _prefs.setString('security.lock_timing', value.wireName);
    notifyListeners();
  }

  Future<void> setAppLockGraceSeconds(int value) async {
    await _prefs.setInt('security.lock_grace_seconds', value);
    notifyListeners();
  }

  /// Records the lock closing or opening.
  ///
  /// Deliberately silent — no [notifyListeners]. The lock gate is the thing
  /// that sets this, and telling it that something changed while it is
  /// changing it is how a rebuild loop starts.
  Future<void> setAppLockClosed(bool value) =>
      _prefs.setBool('security.lock_closed', value);

  Future<void> setAppLockLeftAt(DateTime? value) async {
    if (value == null) {
      await _prefs.remove('security.lock_left_at');
    } else {
      await _prefs.setInt(
        'security.lock_left_at',
        value.millisecondsSinceEpoch,
      );
    }
  }

  Future<void> setAppLockBiometricOnly(bool value) async {
    await _prefs.setBool('security.biometric_only', value);
    if (value) await _prefs.setBool('security.app_lock', true);
    notifyListeners();
  }
}
