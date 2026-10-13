import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/screens/security_screen.dart';

/// Settings → Security: the lock is turned off only with the fingerprint, and
/// so is anything that makes it close less often — "Only when I ask" was one
/// tap away from anyone holding the phone with Nex open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NexPreferences preferences;
  late _Device device;

  Future<void> open(WidgetTester tester, Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      'security.app_lock': true,
      ...values,
    });
    preferences = await NexPreferences.load();
    device = _Device();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SecurityScreen(preferences: preferences, lock: device),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('closing later asks first, and a refusal changes nothing', (
    tester,
  ) async {
    await open(tester, {'security.lock_timing': 'immediately'});
    device.answer = false;
    await tester.tap(find.text('Only when I ask'));
    await tester.pumpAndSettle();
    expect(device.asked, 1);
    expect(preferences.appLockTiming, AppLockTiming.immediately);

    device.answer = true;
    await tester.tap(find.text('Only when I ask'));
    await tester.pumpAndSettle();
    expect(device.asked, 2);
    expect(preferences.appLockTiming, AppLockTiming.manual);
  });

  testWidgets('closing sooner does not ask', (tester) async {
    await open(tester, {'security.lock_timing': 'manual'});
    await tester.tap(find.text('As soon as I leave'));
    await tester.pumpAndSettle();
    expect(device.asked, 0);
    expect(preferences.appLockTiming, AppLockTiming.immediately);
  });

  testWidgets('a longer wait asks, a shorter one does not', (tester) async {
    await open(tester, {
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 60,
    });
    await tester.tap(find.text('5 minutes'));
    await tester.pumpAndSettle();
    expect(device.asked, 1);
    expect(preferences.appLockGraceSeconds, 300);

    await tester.tap(find.text('30 seconds'));
    await tester.pumpAndSettle();
    expect(device.asked, 1);
    expect(preferences.appLockGraceSeconds, 30);
  });

  testWidgets('too many tries is said, not swallowed', (tester) async {
    await open(tester, {'security.lock_timing': 'immediately'});
    device
      ..answer = false
      ..failure = NexAuthFailure.lockedOut;
    await tester.tap(find.text('Only when I ask'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Too many tries. Wait a moment, then try again.'),
      findsOneWidget,
    );
    expect(preferences.appLockTiming, AppLockTiming.immediately);
    await tester.pump(const Duration(seconds: 5));
  });

  test('the phone\'s error codes, read', () {
    expect(
      AppLockService.failureOf(auth_error.lockedOut),
      NexAuthFailure.lockedOut,
    );
    expect(
      AppLockService.failureOf(auth_error.permanentlyLockedOut),
      NexAuthFailure.lockedOutHard,
    );
    for (final code in [
      auth_error.notAvailable,
      auth_error.notEnrolled,
      auth_error.passcodeNotSet,
    ]) {
      expect(AppLockService.failureOf(code), NexAuthFailure.unavailable);
    }
    expect(AppLockService.failureOf('somethingElse'), isNull);
  });
}

class _Device extends AppLockService {
  bool answer = true;
  NexAuthFailure? failure;
  int asked = 0;

  @override
  Future<bool> supportsDeviceAuthentication() async => true;

  @override
  Future<bool> supportsBiometrics() async => true;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    asked++;
    lastFailure = answer ? null : failure;
    return answer;
  }
}
