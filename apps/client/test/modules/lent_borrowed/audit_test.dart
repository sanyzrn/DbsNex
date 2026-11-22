import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/cards_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loan_people.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/payment_cards.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';
import 'package:nex_client/modules/lent_borrowed/split_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/split_math.dart';
import 'package:nex_client/modules/lent_borrowed/split_model.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'loans_test_tools.dart';

/// What this audit changed, one behaviour at a time: the wording a filter
/// says when it is empty, asking the person I owe for their card, a settled
/// record dated in the future, adding to a person's page, editing a split
/// that is already saved, and a settle-up that stays recorded.
void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_audit_'),
  );
  tearDown(() => harness.dispose());

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<NexModuleStore> store() async =>
      NexModuleStore(harness.services, 'lent_borrowed');

  String day(int offset) =>
      civilDateKey(DateTime.now().add(Duration(days: offset)));

  Future<void> putLoan(
    NexModuleStore store,
    String id, {
    String person = 'Sara',
    String direction = 'lent',
    int amount = 500000,
    String type = 'money',
    String what = '',
    String? due,
    String? issued,
  }) => store.put('loan', id, {
    'v': 2,
    'currency': 'IRR',
    'currencyDecimals': 0,
    'direction': direction,
    'person': person,
    'type': type,
    'amount': amount,
    'what': what,
    'issued': issued ?? day(-10),
    'due': due,
    'note': '',
  });

  group('an empty filter says what it means', () {
    testWidgets('Overdue with nothing late is not a failed search', (
      tester,
    ) async {
      final s = await store();
      await putLoan(s, 'l1', due: day(10));
      await tester.pumpWidget(app(LoansScreen(store: s)));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('loans-filter-overdue')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is overdue.'), findsOneWidget);
      expect(find.text('Nothing matches that'), findsNothing);

      // A search with no answer still says so.
      await tester.enterText(find.byKey(const ValueKey('loans-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches that'), findsOneWidget);
    });
  });

  group('the record', () {
    testWidgets('owing money asks for the card to pay to', (tester) async {
      final s = await store();
      await s.put('card', 'sara', {
        'v': 1,
        'person': 'Sara',
        'holder': 'Sara A.',
        'card': '6037991234567893',
        'iban': '',
      });
      await putLoan(s, 'l1', direction: 'borrowed', amount: 500000);
      await tester.pumpWidget(app(LoanDetailScreen(store: s, loanId: 'l1')));
      await settleLoans(tester);

      final action = find.byKey(const ValueKey('loan-pay-message'));
      await revealInLoanDetail(tester, action);
      expect(find.text('Ask to pay'), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.textContaining('settle 50,000 tomans'), findsOneWidget);
      expect(find.textContaining('6037 9912 3456 7893'), findsOneWidget);
      expect(find.textContaining('Pay to:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settled record dated in the future keeps a real date', (
      tester,
    ) async {
      final s = await store();
      final tomorrow = day(1);
      await putLoan(s, 'l1', issued: tomorrow);
      await tester.pumpWidget(app(LoanDetailScreen(store: s, loanId: 'l1')));
      await settleLoans(tester);

      final button = find.byKey(const ValueKey('loan-mark-settled'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settleLoans(tester);

      final returns = await s.list('return');
      expect(returns, hasLength(1));
      // The return cannot precede the loan; it is dated the day it starts.
      expect(returns.single.body['date'], tomorrow);
      expect(returns.single.body['amount'], 500000);
    });
  });

  group('a person\u2019s page', () {
    testWidgets('adds a record with the name already written', (tester) async {
      final s = await store();
      await putLoan(s, 'l1');
      await tester.pumpWidget(app(PersonScreen(store: s, personKey: 'sara')));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('person-new')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('loan-field-person')),
      );
      expect(field.controller!.text, 'Sara');

      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '25000',
      );
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await settleLoans(tester);

      final loans = await s.list('loan');
      expect(loans, hasLength(2));
      expect(loans.first.body['person'], 'Sara');
      expect(tester.takeException(), isNull);
    });

    testWidgets('says how the two directions net out', (tester) async {
      final s = await store();
      await putLoan(s, 'l1', amount: 500000);
      await putLoan(s, 'l2', direction: 'borrowed', amount: 200000);
      await tester.pumpWidget(app(PersonScreen(store: s, personKey: 'sara')));
      await settleLoans(tester);

      final net = find.byKey(const ValueKey('person-net-IRR'));
      expect(net, findsOneWidget);
      final text = (tester.widget<Text>(net)).data!;
      expect(text, contains('30,000 tomans'));
      expect(text, contains('in your favour'));
    });

    testWidgets('the people page finds one name among many', (tester) async {
      final s = await store();
      await putLoan(s, 'l1');
      await putLoan(s, 'l2', person: 'Ali');
      await tester.pumpWidget(app(PeopleScreen(store: s)));
      await settleLoans(tester);
      expect(find.byKey(const ValueKey('person-ali')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('people-search')),
        'sar',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('person-sara')), findsOneWidget);
      expect(find.byKey(const ValueKey('person-ali')), findsNothing);
    });
  });

  group('the card book', () {
    testWidgets('editing a card says so', (tester) async {
      final s = await store();
      await s.put('card', 'sara', {
        'v': 1,
        'person': 'Sara',
        'holder': '',
        'card': '6037991234567893',
        'iban': '',
      });
      await tester.pumpWidget(app(CardsScreen(store: s)));
      await settleLoans(tester);
      await tester.tap(find.byKey(const ValueKey('card-sara')));
      await tester.pumpAndSettle();
      // The button that opened the sheet says "Add a card"; the sheet that
      // is correcting one says what it is doing.
      expect(find.text('Edit card'), findsOneWidget);
    });

    test('a second card for one person updates the first', () async {
      final s = await store();
      await s.put('card', 'sara', {
        'v': 1,
        'person': 'Sara',
        'holder': '',
        'card': '6037991234567893',
        'iban': '',
      });
      await saveCard(
        s,
        const PaymentCard(
          id: 'typed',
          person: ' sara ',
          holder: 'Sara A.',
          card: '6037991234567893',
          iban: 'IR820540102680020817909002',
        ),
      );
      final cards = await s.list('card');
      expect(cards, hasLength(1));
      expect(cards.single.id, 'sara');
      expect(cards.single.body['iban'], 'IR820540102680020817909002');
    });
  });

  group('a saved split', () {
    Future<NexModuleStore> seededSplit() async {
      final s = await store();
      await s.put('split', 's1', {
        'v': 1,
        'title': 'Trip',
        'date': '2026-11-01',
        'me': 'Ali',
        'people': ['Ali', 'Sara'],
        'costs': [
          {
            'id': 'c1',
            'title': 'Dinner',
            'receipt': {'id': 'future-metadata'},
            'amount': 300000,
            'payer': 'Ali',
            'mode': 'equal',
            'parts': {'Ali': 0, 'Sara': 0},
          },
        ],
        // A field from a later version is written back untouched.
        'weather': 'sunny',
      });
      return s;
    }

    testWidgets('a cost is corrected in place', (tester) async {
      final s = await seededSplit();
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('split-cost-c1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('split-cost-amount')),
        '40000',
      );
      await tester.tap(find.byKey(const ValueKey('split-cost-save')));
      await settleLoans(tester);

      final split = LoanSplit.fromRecord((await s.list('split')).single);
      expect(split.costs.single.amount, 400000);
      expect(split.costs.single.id, 'c1');
      final raw = (await s.list('split')).single.body;
      expect(raw['weather'], 'sunny');
      expect((raw['costs'] as List).single['receipt'], {
        'id': 'future-metadata',
      });
      // 400,000 rials shared equally: 20,000 tomans each way.
      expect(find.textContaining('20,000 tomans'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cost added later is kept', (tester) async {
      final s = await seededSplit();
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('split-cost-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('split-cost-name')),
        'Taxi',
      );
      await tester.enterText(
        find.byKey(const ValueKey('split-cost-amount')),
        '20000',
      );
      await tester.tap(find.byKey(const ValueKey('split-cost-save')));
      await settleLoans(tester);

      final split = LoanSplit.fromRecord((await s.list('split')).single);
      expect(split.costs, hasLength(2));
      expect((await s.list('split')).single.body['weather'], 'sunny');
      expect(find.textContaining('Taxi'), findsOneWidget);
    });

    testWidgets('the whole split is renamed from its page', (tester) async {
      final s = await seededSplit();
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('split-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit split'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('split-field-title')),
        'Weekend trip',
      );
      await tester.tap(find.byKey(const ValueKey('split-save')));
      await settleLoans(tester);

      final raw = (await s.list('split')).single;
      expect(raw.body['title'], 'Weekend trip');
      expect((raw.body['costs'] as List).single['receipt'], {
        'id': 'future-metadata',
      });
      expect(raw.body['weather'], 'sunny');
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing someone keeps exact shares intact', (tester) async {
      final s = await seededSplit();
      final raw = (await s.get('split', 's1'))!;
      await s.put('split', 's1', {
        ...raw,
        'people': ['Ali', 'Sara', 'Reza'],
        'costs': [
          {
            ...(raw['costs'] as List).single as Map<String, Object?>,
            'mode': 'amounts',
            'parts': {'Ali': 100000, 'Sara': 100000, 'Reza': 100000},
          },
        ],
      });
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);
      await tester.tap(find.byKey(const ValueKey('split-edit')));
      await tester.pumpAndSettle();
      final chip = find.byKey(const ValueKey('split-person-Sara'));
      tester.widget<InputChip>(chip).onDeleted!();
      await tester.pumpAndSettle();

      expect(chip, findsOneWidget);
      expect(
        find.text('Edit the costs assigned to Sara before removing them.'),
        findsOneWidget,
      );
    });

    testWidgets('a payment recorded yesterday still reads as recorded', (
      tester,
    ) async {
      final s = await seededSplit();
      final split = LoanSplit.fromBody('s1', (await s.get('split', 's1'))!);
      final transfer = settleTransfers(split).single;
      await putLoan(
        s,
        'l1',
        person: 'Sara',
        amount: transfer.amount,
        issued: day(-1),
      );
      await s.put('loan', 'l1', {
        ...(await s.get('loan', 'l1'))!,
        'note': splitNote(split, 'Settle up'),
      });

      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);
      expect(find.text('Recorded'), findsOneWidget);
      expect(find.text('Record as a loan'), findsNothing);

      // The disabled button cannot make a second record.
      await tester.tap(find.byKey(const ValueKey('split-record-0')));
      await tester.pumpAndSettle();
      expect(await s.list('loan'), hasLength(1));
    });

    testWidgets('a renamed split keeps its settle-up recorded', (tester) async {
      final s = await seededSplit();
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('split-record-0')));
      await settleLoans(tester);
      // The loan points back at the split it came from, not only at its name.
      expect((await s.list('loan')).single.body['split'], 's1');

      await tester.tap(find.byKey(const ValueKey('split-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('split-field-title')),
        'Weekend trip',
      );
      await tester.tap(find.byKey(const ValueKey('split-save')));
      await settleLoans(tester);

      expect(find.text('Recorded'), findsOneWidget);
      expect(find.text('Record as a loan'), findsNothing);
      expect(await s.list('loan'), hasLength(1));
    });

    testWidgets('leaving a half-written split asks first', (tester) async {
      final s = await store();
      await tester.pumpWidget(app(LoansScreen(store: s)));
      await settleLoans(tester);
      await tester.tap(find.byKey(const ValueKey('loans-units')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Splits'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('splits-empty-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('split-field-title')),
        'Trip',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this split?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('split-save')), findsNothing);
      expect(await s.list('split'), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an untouched split editor closes without a question', (
      tester,
    ) async {
      final s = await seededSplit();
      await tester.pumpWidget(app(SplitDetailScreen(store: s, splitId: 's1')));
      await settleLoans(tester);
      await tester.tap(find.byKey(const ValueKey('split-edit')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard this split?'), findsNothing);
      expect(find.byKey(const ValueKey('split-save')), findsNothing);
      expect((await s.list('split')).single.body['title'], 'Trip');
      expect(tester.takeException(), isNull);
    });
  });

  group('the arithmetic behind the page', () {
    test('two directions net out, one direction keeps its own line', () {
      const owed = LoanSummary(
        money: [CurrencyTotal('IRR', 0, 500000)],
        itemsOut: 0,
        open: 1,
        overdue: 0,
      );
      const owe = LoanSummary(
        money: [CurrencyTotal('IRR', 0, 200000)],
        itemsOut: 0,
        open: 1,
        overdue: 0,
      );
      expect(LoanSummary.net(owed, owe).single.minor, 300000);
      expect(LoanSummary.net(owe, owed).single.minor, -300000);
      expect(
        LoanSummary.net(
          owed,
          const LoanSummary(money: [], itemsOut: 0, open: 0, overdue: 0),
        ),
        isEmpty,
      );
    });

    test('net balances reconcile different decimal scales in one currency', () {
      const owed = LoanSummary(
        money: [
          CurrencyTotal('USD', 2, 1234),
          CurrencyTotal('USD', 0, 5),
          CurrencyTotal('EUR', 2, 1000),
        ],
        itemsOut: 0,
        open: 3,
        overdue: 0,
      );
      const owing = LoanSummary(
        money: [CurrencyTotal('USD', 3, 12500)],
        itemsOut: 0,
        open: 1,
        overdue: 0,
      );
      final net = LoanSummary.net(owed, owing).single;
      expect((net.currency, net.digits, net.minor), ('USD', 3, 4840));
    });

    test('a recorded transfer is matched without its date', () {
      final split = LoanSplit.fromBody('s1', {
        'title': 'Trip',
        'me': 'Ali',
        'people': ['Ali', 'Sara'],
        'costs': [
          {
            'id': 'c1',
            'amount': 300000,
            'payer': 'Ali',
            'mode': 'equal',
            'parts': {'Ali': 0, 'Sara': 0},
          },
        ],
      });
      final transfer = settleTransfers(split).single;
      Loan loan({
        String person = 'Sara',
        int amount = 150000,
        String note = 'x',
        String direction = 'lent',
        String issued = '2020-01-01',
        String splitId = '',
        String currency = 'IRR',
      }) => Loan(
        id: 'l1',
        direction: LoanDirection.fromKey(direction),
        person: person,
        kind: LoanKind.money,
        amount: amount,
        what: '',
        issued: issued,
        due: null,
        note: note,
        splitId: splitId,
        currency: currency,
      );
      final note = splitNote(split, 'Settle up');
      expect(
        splitTransferRecorded([loan(note: note)], split, transfer, 'Settle up'),
        isTrue,
      );
      expect(
        splitTransferRecorded(
          [loan(note: note, direction: 'borrowed')],
          split,
          transfer,
          'Settle up',
        ),
        isFalse,
      );
      expect(
        splitTransferRecorded(
          [loan(note: note, amount: 1)],
          split,
          transfer,
          'Settle up',
        ),
        isFalse,
      );
      expect(
        splitTransferRecorded(
          [loan(note: note, person: 'Reza')],
          split,
          transfer,
          'Settle up',
        ),
        isFalse,
      );
      expect(
        splitTransferRecorded(
          [loan(note: note, currency: 'USD')],
          split,
          transfer,
          'Settle up',
        ),
        isFalse,
      );
      // Linked to this split: a rename cannot unrecord it.
      expect(
        splitTransferRecorded(
          [loan(note: 'Settle up: Weekend trip', splitId: split.id)],
          split,
          transfer,
          'Settle up',
        ),
        isTrue,
      );
      // Linked to another split: same shape, different payment.
      expect(
        splitTransferRecorded(
          [loan(note: note, splitId: 'other')],
          split,
          transfer,
          'Settle up',
        ),
        isFalse,
      );
    });

    test('bucketing returns once answers exactly what each call did', () {
      final loans = [
        Loan(
          id: 'a',
          direction: LoanDirection.lent,
          person: 'Sara',
          kind: LoanKind.money,
          amount: 500000,
          what: '',
          issued: '2026-01-01',
          due: null,
          note: '',
        ),
      ];
      final returns = [
        const LoanReturn(
          id: 'r1',
          loanId: 'a',
          date: '2026-01-02',
          amount: 100000,
        ),
      ];
      final once = LoanSummary.of(loans, returns);
      final bucketed = LoanSummary.ofBucketed(
        loans,
        LoanMath.returnsByLoan(returns),
      );
      expect(bucketed.money.single.minor, once.money.single.minor);
      expect(bucketed.open, once.open);
      expect(bucketed.itemsOut, once.itemsOut);
    });
  });
}
