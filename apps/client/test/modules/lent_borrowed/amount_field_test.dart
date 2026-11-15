import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/amount_field.dart';
import 'package:nex_client/modules/lent_borrowed/irr_unit.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The amount is grouped as it is typed and said in words underneath, and
/// the whole module can say Iranian amounts in toman or in rial.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_amt_'),
  );
  tearDown(() => harness.dispose());

  Widget app(Locale locale, Widget home) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> pumpField(
    WidgetTester tester, {
    required IrrUnit unit,
    Locale locale = const Locale('en'),
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        locale,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: AmountField(
              controller: controller,
              currency: 'IRR',
              digits: 0,
              unit: unit,
              label: 'Amount',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('toman: grouped digits and the same amount in words', (
    tester,
  ) async {
    await pumpField(tester, unit: IrrUnit.toman);
    await tester.enterText(find.byType(TextField), '50000');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '50,000',
      reason: 'the field groups as it goes',
    );
    expect(find.text('fifty thousand tomans'), findsOneWidget);
    expect(find.text('tomans'), findsOneWidget, reason: 'the field suffix');
  });

  testWidgets('rial: the same field says rials', (tester) async {
    await pumpField(tester, unit: IrrUnit.rial);
    await tester.enterText(find.byType(TextField), '500000');
    await tester.pumpAndSettle();
    expect(find.text('five hundred thousand rials'), findsOneWidget);
  });

  testWidgets('Persian: the words are Persian and the digits Persian', (
    tester,
  ) async {
    await pumpField(tester, unit: IrrUnit.toman, locale: const Locale('fa'));
    await tester.enterText(find.byType(TextField), '1200000');
    await tester.pumpAndSettle();
    expect(find.text('یک میلیون و دویست هزار تومان'), findsOneWidget);
    // Latin digits typed on a phone keyboard are shown in the script the
    // page is read in, with the Persian separators.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '۱٬۲۰۰٬۰۰۰',
    );
  });

  testWidgets('an empty field asks for the words instead of inventing them', (
    tester,
  ) async {
    await pumpField(tester, unit: IrrUnit.toman);
    expect(find.text('The amount in words appears here.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pumpAndSettle();
    expect(find.text('The amount in words appears here.'), findsOneWidget);
  });

  testWidgets(
    'the module switches between toman and rial without touching data',
    (tester) async {
      final store = NexModuleStore(harness.services, 'lent_borrowed');
      await store.put('loan', 'l1', {
        'direction': 'lent',
        'person': 'Sara',
        'type': 'money',
        'amount': 500000,
        'currency': 'IRR',
        'currencyDecimals': 0,
        'issued': '2026-10-01',
        'due': null,
        'note': '',
      });
      await tester.pumpWidget(
        app(const Locale('en'), LoansScreen(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('50,000 tomans still out'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('loans-units')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rial').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('500,000 rials still out'), findsOneWidget);
      expect(
        (await store.get('loan', 'l1'))?['amount'],
        500000,
        reason: 'the unit is how an amount is said, never what is stored',
      );
      final settings = await store.get('settings', 'settings');
      expect(settings?['irrUnit'], 'rial');

      // And back, so the choice is a choice both ways.
      await tester.tap(find.byKey(const ValueKey('loans-units')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toman').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('50,000 tomans still out'), findsOneWidget);
    },
  );
}
