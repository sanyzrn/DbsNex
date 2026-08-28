import 'package:local_auth/local_auth.dart';

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
