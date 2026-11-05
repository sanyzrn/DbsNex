import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nex_client/platform/app_lock.dart';

void main() {
  test(
    'authentication retains biometric policy and survives backgrounding',
    () async {
      final plugin = _Authentication();
      final lock = AppLockService(authentication: plugin);
      for (final biometricOnly in [false, true]) {
        expect(
          await lock.authenticate(
            reason: 'Unlock',
            biometricOnly: biometricOnly,
          ),
          isTrue,
        );
        expect(plugin.biometric, biometricOnly);
        expect(plugin.persist, isTrue);
        expect(lock.lastFailure, isNull);
      }
    },
  );

  test(
    'typed plugin failures keep the lock closed and explain lockouts',
    () async {
      final plugin = _Authentication();
      final lock = AppLockService(authentication: plugin);
      for (final (code, failure) in [
        (LocalAuthExceptionCode.temporaryLockout, NexAuthFailure.lockedOut),
        (LocalAuthExceptionCode.biometricLockout, NexAuthFailure.lockedOutHard),
        (LocalAuthExceptionCode.noCredentialsSet, NexAuthFailure.unavailable),
        (LocalAuthExceptionCode.userCanceled, null),
      ]) {
        plugin.failure = code;
        expect(
          await lock.authenticate(reason: 'Unlock', biometricOnly: true),
          isFalse,
        );
        expect(lock.lastFailure, failure);
      }
      plugin.failure = null;
      expect(
        await lock.authenticate(reason: 'Unlock', biometricOnly: false),
        isTrue,
      );
      expect(lock.lastFailure, isNull);
    },
  );
}

class _Authentication extends LocalAuthentication {
  bool? biometric;
  bool? persist;
  LocalAuthExceptionCode? failure;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    biometric = biometricOnly;
    persist = persistAcrossBackgrounding;
    final code = failure;
    if (code != null) throw LocalAuthException(code: code);
    return true;
  }
}
