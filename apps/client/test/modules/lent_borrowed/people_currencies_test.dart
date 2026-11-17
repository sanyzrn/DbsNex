import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/irr_unit.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loan_people.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// What each person owes and is owed, **per currency** — two directions
/// never netted against each other, two currencies never added.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_people_cur_'),
  );
  tearDown(() => harness.dispose());

  Loan loan(
    String id,
    String person, {
    LoanDirection direction = LoanDirection.lent,
    int amount = 1000,
    String currency = 'USD',
    int decimals = 2,
    LoanKind kind = LoanKind.money,
    String what = '',
  }) => Loan(
    id: id,
    direction: direction,
    person: person,
    kind: kind,
    amount: amount,
    what: what,
    issued: '2026-10-01',
    due: null,
    note: '',
    currency: currency,
    currencyDecimals: decimals,
  );

  Future<BuildContext> pumpHost(WidgetTester tester, Locale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  String plain(String text) => text.replaceAll(RegExp('[\u2066-\u2069]'), '');

  testWidgets('one line per currency, each direction said apart', (
    tester,
  ) async {
    final context = await pumpHost(tester, const Locale('en'));
    final loans = [
      loan('a', 'Sara', amount: 12500),
      loan('b', 'Sara', amount: 500000, currency: 'IRR', decimals: 0),
      loan('c', 'Sara', direction: LoanDirection.borrowed, amount: 3000),
      loan('d', 'Sara', kind: LoanKind.item, amount: 1, what: 'Drill'),
    ];
    final people = peopleOf(loans, const []);
    final lines = ledgerLines(context, people.single, IrrUnit.toman);
    // One currency per line: joining them into one sentence read wrong in
    // Persian, and a count of things is not a currency at all.
    expect(lines, hasLength(4));
    expect(plain(lines[0]), 'Owes you 50,000 tomans');
    expect(plain(lines[1]), 'Owes you 125.00 USD');
    expect(plain(lines[2]), '1 item still out');
    expect(plain(lines[3]), 'You owe 30.00 USD');
  });

  testWidgets('the same numbers in rial, never mixed', (tester) async {
    final context = await pumpHost(tester, const Locale('fa'));
    final loans = [
      loan('a', 'سارا', amount: 500000, currency: 'IRR', decimals: 0),
      loan(
        'b',
        'سارا',
        direction: LoanDirection.borrowed,
        amount: 300000,
        currency: 'IRR',
        decimals: 0,
      ),
    ];
    final people = peopleOf(loans, const []);
    final lines = ledgerLines(context, people.single, IrrUnit.rial);
    expect(lines.first, contains('۵۰۰٬۰۰۰ ریال'));
    expect(lines.last, contains('۳۰۰٬۰۰۰ ریال'));
  });

  testWidgets('nothing between you is said plainly, not as zero', (
    tester,
  ) async {
    final context = await pumpHost(tester, const Locale('en'));
    final loans = [loan('a', 'Ali', amount: 500)];
    final returns = [
      const LoanReturn(id: 'r', loanId: 'a', date: '2026-10-02', amount: 500),
    ];
    final people = peopleOf(loans, returns);
    expect(ledgerLines(context, people.single, IrrUnit.toman), ['All settled']);
  });

  testWidgets('the people page shows both directions per currency', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    Future<void> put(String id, String direction, int amount, String code) =>
        store.put('loan', id, {
          'person': 'Sara',
          'direction': direction,
          'type': 'money',
          'amount': amount,
          'currency': code,
          'currencyDecimals': code == 'IRR' ? 0 : 2,
          'issued': '2026-10-01',
          'due': null,
          'note': '',
        });
    await put('a', 'lent', 500000, 'IRR');
    await put('b', 'borrowed', 12500, 'USD');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PeopleScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Owes you 50,000 tomans'), findsOneWidget);
    expect(find.textContaining('You owe 125.00'), findsOneWidget);
  });

  testWidgets('the chevron points where the page continues', (tester) async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    await store.put('loan', 'a', {
      'person': 'Sara',
      'direction': 'lent',
      'type': 'money',
      'amount': 500000,
      'currency': 'IRR',
      'currencyDecimals': 0,
      'issued': '2026-10-01',
      'due': null,
      'note': '',
    });
    for (final locale in const [Locale('en'), Locale('fa')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PeopleScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      // The icon widget is the same in both; the material chevron mirrors
      // itself under RTL, which is how forward reads in Persian.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    }
  });
}
