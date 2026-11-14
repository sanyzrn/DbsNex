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
  ///
  /// Bound to the range the Security screen offers, on the way in and on
  /// the way out (SEC-06): the value travels in preferences backups and a
  /// restored file that says 68 years would have turned "after a minute"
  /// into "never" without anything on screen looking different. A value
  /// that is too small fails the other way — it just locks sooner — but
  /// both are pulled into the range where the answer is one the user chose.
  static const minGraceSeconds = 15;
  static const maxGraceSeconds = 3600;

  int get appLockGraceSeconds {
    final value = _prefs.getInt('security.lock_grace_seconds') ?? 60;
    return value < minGraceSeconds || value > maxGraceSeconds ? 60 : value;
  }

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
    // Stored as given, read back inside the range: the Security screen only
    // ever writes one of its own choices, and a value that did not come
    // from there is not made canonical by rewriting it.
    await _prefs.setInt('security.lock_grace_seconds', value);
    notifyListeners();
  }

  /// Records the lock closing or opening.
  ///
  /// Deliberately silent — no [notifyListeners]. The lock gate is the thing
  /// that sets this, and telling it that something changed while it is
  /// changing it is how a rebuild loop starts.
  ///
  /// A write that would say what the store already says is skipped: this is
  /// written on every launch and every preference refresh, and a flush of
  /// an unchanged `false` was the most regular disk write the app made.
  Future<void> setAppLockClosed(bool value) async {
    if (appLockClosed == value) return;
    await _prefs.setBool('security.lock_closed', value);
  }

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
