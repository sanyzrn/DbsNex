import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/security_tools/secret_screen.dart';

/// A generated password is a secret from the moment it is on screen (SEC-02).
/// The Tools page's generator blocked screen capture while open; since 2.8.1
/// the Security toolbox's generator is the only one, and it does the same.
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
        home: SecurityGenerator(),
      ),
    );
    await tester.pump();
    expect(secure, [true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(secure, [true, false]);
  });
}
