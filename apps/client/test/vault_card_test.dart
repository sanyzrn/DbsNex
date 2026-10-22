import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/vault_banks.dart';
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

/// The bank-card editor: what stops a save, what only warns, and when an
/// edit counts as unfinished.
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

  VaultEntry card({String id = 'a', Map<String, String>? fields}) => VaultEntry(
    id: id,
    kind: VaultKind.card,
    fields: fields ?? {'title': 'Salary', 'number': '4111111111111111'},
    updatedAt: DateTime.utc(2026),
  );

  group('card numbers', () {
    test('a number only has to look like one to be kept', () {
      // 6104337835468074 is a Bank Mellat number whose last digit does not
      // satisfy the Luhn sum. It used to be refused outright.
      expect(validVaultCardShape('6104337835468074'), isTrue);
      expect(validVaultCard('6104337835468074'), isFalse);
      expect(validVaultCardShape('۶۱۰۴ ۳۳۷۸ ۳۵۴۶ ۸۰۷۴'), isTrue);
      expect(validVaultCardShape('1234'), isFalse);
      expect(validVaultCardShape('1111111111111111'), isFalse);
      expect(validVaultCardShape('61043378354680749999'), isFalse);
      expect(validVaultCard('4111111111111111'), isTrue);
    });

    test('an expiry is a month and a year, either way round', () {
      for (final ok in ['05/27', '5/2027', '۰۵/۲۷', '1405/08', '27/05', '']) {
        expect(validVaultExpiry(ok), isTrue, reason: ok);
      }
      for (final bad in ['13/27', '00/27', '0527', '05-27', '05/2', 'ab/cd']) {
        expect(validVaultExpiry(bad), isFalse, reason: bad);
      }
    });

    test('the first six digits name the bank', () {
      expect(vaultBankFor('6104337835468074')?.en, 'Bank Mellat');
      expect(vaultBankFor('6037991234567890')?.fa, 'بانک ملی ایران');
      expect(vaultBankFor('61043'), isNull);
      expect(vaultBankFor('4111111111111111'), isNull);
    });
  });

  group('what counts as unfinished', () {
    test('nothing typed, nothing changed', () {
      expect(vaultEntryDiffers(card(fields: {}), null), isFalse);
      expect(
        vaultEntryDiffers(card(fields: {'title': '  ', 'bank': ''}), null),
        isFalse,
      );
      final saved = card();
      expect(vaultEntryDiffers(saved, saved), isFalse);
      // The editor adds empty keys and groups the number; neither is a change.
      expect(
        vaultEntryDiffers(
          card(
            fields: {
              'title': 'Salary',
              'number': '4111 1111 1111 1111',
              'bank': '',
              'cvv2': '',
            },
          ),
          saved,
        ),
        isFalse,
      );
    });

    test('anything real is', () {
      expect(vaultEntryDiffers(card(fields: {'title': 'x'}), null), isTrue);
      expect(
        vaultEntryDiffers(
          card(fields: {'title': 'Salary', 'number': '4111'}),
          card(),
        ),
        isTrue,
      );
    });
  });

  Widget app() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VaultScreen(kind: VaultKind.card, authentication: _Auth()),
  );

  Future<void> unlock(WidgetTester tester) async {
    // Tall, so the whole form is built and tappable without scrolling.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();
  }

  testWidgets('opening a saved card and leaving leaves no unfinished edit', (
    tester,
  ) async {
    await VaultStore().save(card());
    await unlock(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('vault-item-a')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vault-field-title')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Continue unfinished edit'), findsNothing);
    // And nothing is blocked: the add button is live.
    final add = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_card),
    );
    expect(add.onPressed, isNotNull);
    expect((await VaultStore().read()).draft, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a new card with nothing filled in leaves nothing behind', (
    tester,
  ) async {
    await unlock(tester);
    await tester.tap(find.text('Add bank card'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Continue unfinished edit'), findsNothing);
    expect((await VaultStore().read()).draft, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('typing and then clearing it again is not unfinished either', (
    tester,
  ) async {
    await unlock(tester);
    await tester.tap(find.text('Add bank card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-title')),
      'x',
    );
    await tester.pump(const Duration(seconds: 1));
    expect((await VaultStore().read()).draft, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('vault-field-title')), '');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Continue unfinished edit'), findsNothing);
    expect((await VaultStore().read()).draft, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a real unfinished edit is still kept to resume', (tester) async {
    await unlock(tester);
    await tester.tap(find.text('Add bank card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-title')),
      'Half done',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Continue unfinished edit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'a number whose check digit is off is warned about and still saved',
    (tester) async {
      await unlock(tester);
      await tester.tap(find.text('Add bank card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault-field-title')),
        'Mellat',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vault-field-number')),
        '۶۱۰۴۳۳۷۸۳۵۴۶۸۰۷۴',
      );
      await tester.pumpAndSettle();
      // Grouped as printed, Latin digits, bank recognised and filled in.
      final number = tester.widget<TextFormField>(
        find.byKey(const ValueKey('vault-field-number')),
      );
      expect(number.controller!.text, '6104 3378 3546 8074');
      expect(find.text('Looks like Bank Mellat'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('vault-field-bank')),
            )
            .controller!
            .text,
        'Bank Mellat',
      );
      expect(find.textContaining('last digit'), findsOneWidget);

      await tester.ensureVisible(find.text('Save securely'));
      await tester.tap(find.text('Save securely'));
      await tester.pumpAndSettle();
      final saved = (await VaultStore().read()).entries.single;
      expect(saved.value('number'), '6104337835468074');
      expect(saved.value('bank'), 'Bank Mellat');
      expect(find.text('6104 3378 3546 8074'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('a bank name the person typed is never overwritten', (
    tester,
  ) async {
    await unlock(tester);
    await tester.tap(find.text('Add bank card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-bank')),
      'My own name',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vault-field-number')),
      '6104337835468074',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('vault-field-bank')))
          .controller!
          .text,
      'My own name',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
