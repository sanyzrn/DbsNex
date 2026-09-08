import 'package:local_auth/local_auth.dart';

import 'nex_preferences.dart';

/// Whether a cold start opens onto the lock.
///
/// A launch is not a resume: the process died, so nothing is in memory and
/// the only record of where the lock stood is the one written to disk. All
/// three timings answer this from persisted facts — a lock that was closed
/// stays closed, and a grace period is measured against the wall clock rather
/// than against how long this process happened to live.
///
/// Here rather than inside the app's own state because two things ask it, and
/// they must not answer differently: the gate, which decides what to draw,
/// and bootstrap, which writes the home-screen widget's snapshot *before* the
/// gate exists. When those disagreed, a locked library's notes reached the
/// widget file for as long as it took the first frame to arrive.
bool nexLockClosedOnLaunch(NexPreferences preferences) {
  if (!preferences.appLockEnabled) return false;
  if (preferences.appLockClosed) return true;
  return switch (preferences.appLockTiming) {
    AppLockTiming.immediately => true,
    AppLockTiming.manual => false,
    AppLockTiming.after => nexLockGraceHasRunOut(preferences),
  };
}

/// Whether the app has been away longer than the grace period allows.
///
/// [NexPreferences.appLockLeftAt] is the last moment Nex is known to have
/// been open — written when it goes to the background and again when it comes
/// back, because "how long has it been away" is measured from either. Never
/// recorded at all is a first launch, or an install predating the setting:
/// locking is the safe answer to not knowing.
bool nexLockGraceHasRunOut(NexPreferences preferences) {
  final left = preferences.appLockLeftAt;
  if (left == null) return true;
  final away = DateTime.now().difference(left);
  return away.isNegative || away.inSeconds >= preferences.appLockGraceSeconds;
}

class AppLockService {
  AppLockService({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  Future<bool> supportsDeviceAuthentication() async {
    try {
      return await _authentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> supportsBiometrics() async {
    try {
      if (!await _authentication.canCheckBiometrics) return false;
      return (await _authentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    try {
      return await _authentication.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
