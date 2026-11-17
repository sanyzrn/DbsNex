import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// Every screen of the module on a small phone at text scale 2.0, in
/// Persian right-to-left and in English, light and dark: nothing overflows
/// and nothing is clipped. Large text is where a long amount, a Persian
/// name and a currency word meet.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_big_'),
  );
  tearDown(() => harness.dispose());

  Future<NexModuleStore> seed() async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    final now = DateTime.now();
    String key(int offset) {
      final day = DateTime(now.year, now.month, now.day + offset);
      return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
    }

    await store.put('loan', 'l1', {
      'person': 'سارا محمدی‌نژاد',
      'direction': 'lent',
      'type': 'money',
      'amount': 1234567890,
      'currency': 'IRR',
      'currencyDecimals': 0,
      'issued': key(-30),
      'due': key(-2),
      'note': 'برای خرید کتاب‌های دانشگاه، نیمی از مبلغ بعداً',
    });
    await store.put('return', 'r1', {
      'loan': 'l1',
      'amount': 234567890,
      'date': key(-5),
    });
    await store.put('loan', 'l2', {
      'person': 'سارا محمدی‌نژاد',
      'direction': 'borrowed',
      'type': 'item',
      'amount': 2,
      'what': 'کوله‌پشتی بزرگ آبی',
      'issued': key(-3),
      'due': key(2),
      'note': '',
    });
    return store;
  }

  Widget app(Locale locale, Brightness brightness, Widget home) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: home,
  );

  for (final locale in [const Locale('fa'), const Locale('en')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'the detail page at 2.0 (${locale.languageCode} $brightness)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = await seed();
          await tester.pumpWidget(
            app(
              locale,
              brightness,
              LoanDetailScreen(store: store, loanId: 'l1'),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // All the way down: the history, the reminder and the buttons.
          for (var i = 0; i < 6; i++) {
            await tester.drag(
              find.byKey(const ValueKey('loan-detail-body')),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('the people pages at 2.0, Persian dark', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await seed();
    await tester.pumpWidget(
      app(const Locale('fa'), Brightness.dark, PeopleScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('person-ledger')), findsOneWidget);
  });

  testWidgets('the message sheet at 2.0, Persian dark', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await seed();
    await tester.pumpWidget(
      app(
        const Locale('fa'),
        Brightness.dark,
        LoanDetailScreen(store: store, loanId: 'l1'),
      ),
    );
    await tester.pumpAndSettle();
    final message = find.byKey(const ValueKey('loan-message'));
    await tester.dragUntilVisible(
      message,
      find.byKey(const ValueKey('loan-detail-body')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(message);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('loan-message-copy')), findsOneWidget);
  });

  testWidgets('the overview at 2.0, Persian dark', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await seed();
    await tester.pumpWidget(
      app(const Locale('fa'), Brightness.dark, LoansScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
