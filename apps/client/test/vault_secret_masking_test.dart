import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/vault_session.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'package:nex_client/screens/vault_screen.dart';

class _Auth extends AppLockService {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => true;
}

/// A password on a vault screen: dots by default, readable for a few
/// seconds through the eye, and never in the clear in the list.
///
/// `secret` used to choose the keyboard and nothing else — the value sat in
/// plain sight in both the list and the editor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    VaultSession.instance
      ..close()
      ..clock = DateTime.now;
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  VaultEntry login({String id = 'p'}) => VaultEntry(
    id: id,
    kind: VaultKind.password,
    fields: {
      'title': 'Email',
      'login': 'someone@example.com',
      'password': 'hunter2',
    },
    updatedAt: DateTime.utc(2026),
  );

  Widget app() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VaultScreen(kind: VaultKind.password, authentication: _Auth()),
  );

  Future<void> unlock(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();
  }

  testWidgets('the list masks the password; the eye lends it seconds', (
    tester,
  ) async {
    await VaultStore().save(login());
    await unlock(tester);

    // Dots of no particular length — the length of a password is itself a
    // fact about it — and never the word itself.
    expect(find.text('hunter2'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pumpAndSettle();
    expect(find.text('hunter2'), findsOneWidget);

    // The reveal is a loan, not a setting: it covers itself back up.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('hunter2'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('the editor masks what is typed, with an eye to read it back', (
    tester,
  ) async {
    await VaultStore().save(login());
    await unlock(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('vault-item-p')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();

    TextField field() => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('vault-field-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(field().obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(field().obscureText, isFalse);
    // Still the same eye, pressed again, and the mask is back.
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(field().obscureText, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
