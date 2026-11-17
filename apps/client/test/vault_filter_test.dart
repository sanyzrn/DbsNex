import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/vault_session.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'package:nex_client/screens/vault_screen.dart';

/// NEX-UI-04: the vault's list is filtered, sorted and remembered across the
/// rebuilds that change nothing about it — a copy tap's feedback, a reveal
/// toggle — which used to re-run the whole join→toLowerCase→contains→sort
/// pass per keystroke and per feedback tick. This file pins what the filter
/// itself must answer; the memo is keyed on everything it reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VaultEntry entry(
    String id, {
    Map<String, String> fields = const {},
    DateTime? updated,
    bool favorite = false,
  }) => VaultEntry(
    id: id,
    kind: VaultKind.password,
    fields: fields,
    updatedAt: updated ?? DateTime.utc(2026, 1, 1),
    favorite: favorite,
  );

  final alpha = entry(
    'a',
    fields: {
      'title': 'Alpha bank',
      'login': 'alpha@example.test',
      'website': 'alpha.example.org',
    },
    updated: DateTime.utc(2026, 1, 3),
  );
  final beta = entry(
    'b',
    fields: {
      'title': 'Beta shop',
      'login': 'beta@example.test',
      'website': 'beta.example.org',
    },
    updated: DateTime.utc(2026, 1, 2),
  );
  final gamma = entry(
    'g',
    fields: {'title': 'Gamma', 'website': 'gamma.example.org'},
    updated: DateTime.utc(2026, 1, 1),
  );

  Future<void> unlocked(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VaultScreen(
          kind: VaultKind.password,
          authentication: _AlwaysTrueAuth(),
        ),
      ),
    );
    // Bounded pumps: the locked screen keeps a placeholder shimmer while
    // the store read is in flight, and a shimmer never settles by design.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Unlock vault'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    VaultSession.instance
      ..close()
      ..clock = DateTime.now;
    // The secure-window channel must answer, the way the vault's own test
    // file mocks it: without a handler the surface "fails" and the vault
    // refuses to unlock, which is its designed behaviour, not this file's
    // subject.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nex/os_capture'),
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nex/os_capture'), null);
  });

  testWidgets('an empty query shows everything, newest first', (tester) async {
    await VaultStore().save(alpha);
    await VaultStore().save(beta);
    await VaultStore().save(gamma);
    await unlocked(tester);

    expect(find.text('Alpha bank'), findsOneWidget);
    expect(find.text('Beta shop'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);

    // updatedAt, newest first — same order on screen.
    final a = tester.getTopLeft(find.text('Alpha bank')).dy;
    final b = tester.getTopLeft(find.text('Beta shop')).dy;
    final g = tester.getTopLeft(find.text('Gamma')).dy;
    expect(a, lessThan(b));
    expect(b, lessThan(g));
  });

  testWidgets('a query matches the title, the login and the website', (
    tester,
  ) async {
    await VaultStore().save(alpha);
    await VaultStore().save(beta);
    await VaultStore().save(gamma);
    await unlocked(tester);
    final field = find.byType(TextField);

    // Title.
    await tester.enterText(field, 'beta shop');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Beta shop'), findsOneWidget);
    expect(find.text('Alpha bank'), findsNothing);

    // Login — a field the row does not even display.
    await tester.enterText(field, 'alpha@example');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Alpha bank'), findsOneWidget);
    expect(find.text('Beta shop'), findsNothing);

    // Website.
    await tester.enterText(field, 'gamma.example');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Alpha bank'), findsNothing);

    // Clearing the query goes back to everything.
    await tester.enterText(field, '');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Alpha bank'), findsOneWidget);
    expect(find.text('Beta shop'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('favorites first, and the favorites-only view', (tester) async {
    final store = VaultStore();
    await store.save(entry('f', fields: {'title': 'Favourite one'}));
    await store.save(
      entry('o', fields: {'title': 'Other one'}, favorite: true),
    );
    await store.save(entry('n', fields: {'title': 'Neither'}));
    await unlocked(tester);

    // Favourite first regardless of the same updatedAt.
    final f = tester.getTopLeft(find.text('Favourite one')).dy;
    final o = tester.getTopLeft(find.text('Other one')).dy;
    expect(o, lessThan(f));

    // The favorites-only view keeps only the favourite — and a query on
    // top of it narrows within it.
    await tester.tap(find.byIcon(Icons.star_outline_rounded));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Other one'), findsOneWidget);
    expect(find.text('Favourite one'), findsNothing);

    await tester.enterText(find.byType(TextField), 'favourite');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Other one'), findsNothing);

    await tester.enterText(find.byType(TextField), 'other');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Other one'), findsOneWidget);
  });

  testWidgets('the focus view narrows to the one entry', (tester) async {
    final store = VaultStore();
    await store.save(entry('x', fields: {'title': 'Linked card'}));
    await store.save(entry('y', fields: {'title': 'Everything else'}));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VaultScreen(
          kind: VaultKind.password,
          focusId: 'y',
          authentication: _AlwaysTrueAuth(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Unlock vault'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Everything else'), findsOneWidget);
    expect(find.text('Linked card'), findsNothing);
  });
}

class _AlwaysTrueAuth extends AppLockService {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => true;
}
