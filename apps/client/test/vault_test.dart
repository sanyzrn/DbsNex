import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/secure_window.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'package:nex_client/screens/vault_screen.dart';

class _Auth extends AppLockService {
  _Auth(this.result);
  final Future<bool> result;
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  VaultEntry entry(String id, {String password = 'private-value'}) =>
      VaultEntry(
        id: id,
        kind: VaultKind.password,
        fields: {
          'title': 'Account $id',
          'login': 'user@example.test',
          'password': password,
        },
        updatedAt: DateTime.utc(2026),
      );
  Widget app({AppLockService? auth, Locale locale = const Locale('en')}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VaultScreen(
          kind: VaultKind.password,
          authentication: auth ?? _Auth(Future.value(true)),
        ),
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'concurrent saves, draft recovery and delete retain other records',
    () async {
      final store = VaultStore();
      await Future.wait([
        store.save(entry('one')),
        VaultStore().save(entry('two')),
      ]);
      await store.saveDraft(entry('draft'));
      expect((await VaultStore().read()).entries.map((e) => e.id), [
        'one',
        'two',
      ]);
      expect((await store.read()).draft?.id, 'draft');
      await store.save(entry('draft', password: 'new-private-value'));
      expect((await store.read()).draft, isNull);
      await store.delete('one');
      expect((await store.read()).entries.map((e) => e.id), ['two', 'draft']);
    },
  );
  test('an unreadable vault is never silently replaced', () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: VaultStore.storageKey, value: '{broken');
    await expectLater(VaultStore().read(), throwsFormatException);
    await expectLater(VaultStore().save(entry('one')), throwsFormatException);
    expect(await storage.read(key: VaultStore.storageKey), '{broken');
  });
  test(
    'password generator and card/IBAN validation accept localized digits',
    () {
      final values = {for (var i = 0; i < 100; i++) generateVaultPassword()};
      expect(values.length, 100);
      for (final value in values) {
        expect(value.length, 20);
        expect(RegExp('[a-z]').hasMatch(value), isTrue);
        expect(RegExp('[A-Z]').hasMatch(value), isTrue);
        expect(RegExp('[0-9]').hasMatch(value), isTrue);
        expect(RegExp('[!@#%+_=\\-?]').hasMatch(value), isTrue);
      }
      expect(
        RegExp(
          r'^[a-zA-Z0-9]+$',
        ).hasMatch(generateVaultPassword(symbols: false)),
        isTrue,
      );
      expect(validVaultCard('۴۱۱۱ ۱۱۱۱ ۱۱۱۱ ۱۱۱۱'), isTrue);
      expect(validVaultCard('4111111111111112'), isFalse);
      expect(validVaultCard('0000000000000000'), isFalse);
      expect(validVaultIban('GB82 WEST 1234 5698 7654 32'), isTrue);
      expect(validVaultIban('GB81 WEST 1234 5698 7654 32'), isFalse);
    },
  );
  test(
    'private window leases survive changes to the general app lock',
    () async {
      await NexSecureWindow.setSecure(false);
      await NexSecureWindow.acquirePrivateSurface();
      await NexSecureWindow.setSecure(false);
      expect((calls.last.arguments as Map)['on'], isTrue);
      await NexSecureWindow.releasePrivateSurface();
      expect((calls.last.arguments as Map)['on'], isFalse);
    },
  );
  testWidgets('vault masks credentials and hides all content on background', (
    tester,
  ) async {
    await VaultStore().save(entry('one'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Account one'), findsNothing);
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();
    expect(find.text('Account one'), findsOneWidget);
    await tester.tap(find.text('Account one'));
    await tester.pumpAndSettle();
    expect(find.text('private-value'), findsNothing);
    await tester.tap(find.byTooltip('Reveal'));
    await tester.pump();
    expect(find.text('private-value'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('private-value'), findsNothing);
    expect(find.text('Account one'), findsNothing);
    expect(find.text('Your vault is locked'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('a late authentication reply cannot unlock after backgrounding', (
    tester,
  ) async {
    final result = Completer<bool>();
    await tester.pumpWidget(app(auth: _Auth(result.future)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock vault'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    result.complete(true);
    await tester.pump();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Your vault is locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('unfinished vault text is recovered encrypted after locking', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-title')),
      'Unfinished account',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-password')),
      'draft-secret',
    );
    await tester.tap(find.byTooltip('Lock vault'));
    await tester.pumpAndSettle();
    expect(find.text('Unfinished account'), findsNothing);
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue unfinished edit'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('vault-field-password')),
    );
    expect(field.controller!.text, 'draft-secret');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
