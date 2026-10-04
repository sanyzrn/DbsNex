import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/password_generator_screen.dart';

/// A generated password is a secret from the moment it is on screen, and the
/// generator opens from Tools without the vault's lock (SEC-02).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final secure = <Object?>[];

  setUp(() {
    secure.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setSecure') {
        secure.add((call.arguments as Map<Object?, Object?>)['on']);
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('the generator blocks screen capture while it is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PasswordGeneratorScreen(),
      ),
    );
    await tester.pump();
    expect(secure, [true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(secure, [true, false]);
  });
}
