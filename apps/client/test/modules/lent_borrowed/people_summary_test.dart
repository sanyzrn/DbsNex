import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_filter.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loan_people.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

Loan _loan(
  String id,
  String person, {
  LoanDirection direction = LoanDirection.lent,
  int amount = 1000,
  String currency = 'USD',
  LoanKind kind = LoanKind.money,
  String? due,
  String what = '',
  String note = '',
}) => Loan(
  id: id,
  direction: direction,
  person: person,
  kind: kind,
  amount: amount,
  what: what,
  issued: '2026-10-01',
  due: due,
  note: note,
  currency: currency,
  currencyDecimals: 2,
);

LoanReturn _ret(String loan, int amount) => LoanReturn(
  id: 'r$loan$amount',
  loanId: loan,
  amount: amount,
  date: '2026-10-02',
);

/// A text with the direction marks the formatter wraps a currency in taken
/// out, so a test reads what a person reads.
Finder plainText(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll(RegExp('[\u2066-\u2069]'), '') == text,
);

void main() {
  group('names', () {
    test('one person however it was written', () {
      expect(personKey('  Ali  Reza '), personKey('ali reza'));
      expect(personKey('علي'), personKey('علی'));
      expect(personKey('كيان'), personKey('کیان'));
      expect(personKey('Ali'), isNot(personKey('Alina')));
    });
  });

  group('the summary', () {
    test('keeps each currency by itself and counts what is overdue', () {
      final loans = [
        _loan('a', 'Sara', amount: 10000, currency: 'USD', due: '2020-01-01'),
        _loan('b', 'Sara', amount: 5000, currency: 'USD'),
        _loan('c', 'Reza', amount: 700000, currency: 'IRR'),
        _loan('d', 'Reza', kind: LoanKind.item, amount: 2, what: 'Drill'),
        _loan('e', 'Reza', amount: 100, currency: 'USD'),
      ];
      final summary = LoanSummary.of(loans, [_ret('e', 100), _ret('b', 1000)]);
      final usd = summary.money.firstWhere((t) => t.currency == 'USD');
      // 10000 + (5000 - 1000); the settled one is gone.
      expect(usd.minor, 14000);
      expect(summary.money.map((t) => t.currency).toSet(), {'USD', 'IRR'});
      expect(summary.itemsOut, 1);
      expect(summary.overdue, 1);
      expect(summary.open, 4);
    });

    test('an empty direction is empty', () {
      expect(LoanSummary.of(const [], const []).isEmpty, isTrue);
    });
  });

  group('people', () {
    test('open balances first, directions apart', () {
      final loans = [
        _loan('a', 'Sara', amount: 500),
        _loan('b', 'sara', direction: LoanDirection.borrowed, amount: 200),
        _loan('c', 'Ali', amount: 100),
      ];
      final people = peopleOf(loans, [_ret('c', 100)]);
      expect(people.map((p) => p.key), ['sara', 'ali']);
      final sara = people.first;
      expect(sara.loans, hasLength(2));
      expect(sara.owedToMe.money.single.minor, 500);
      expect(sara.iOwe.money.single.minor, 200);
      expect(people.last.open, isFalse);
    });
  });

  group('filter and search', () {
    final soon = LoanMath.standing(_loan('x', 'A', due: _inDays(2)), const []);
    final late = LoanMath.standing(
      _loan('y', 'A', due: '2020-01-01'),
      const [],
    );
    final done = LoanMath.standing(_loan('z', 'A', amount: 5), [_ret('z', 5)]);

    test('each filter lets through what it names', () {
      expect(LoanFilter.dueSoon.allows(soon), isTrue);
      expect(LoanFilter.dueSoon.allows(late), isFalse);
      expect(LoanFilter.overdue.allows(late), isTrue);
      expect(LoanFilter.settled.allows(done), isTrue);
      expect(LoanFilter.settled.allows(soon), isFalse);
      expect(LoanFilter.all.allows(done), isTrue);
    });

    test('search reads person, item and note', () {
      final loan = _loan(
        'q',
        'Reza',
        kind: LoanKind.item,
        what: 'Blue backpack',
        note: 'For the trip',
      );
      expect(loanMatches(loan, 'rez'), isTrue);
      expect(loanMatches(loan, ' BACKPACK '), isTrue);
      expect(loanMatches(loan, 'trip'), isTrue);
      expect(loanMatches(loan, 'laptop'), isFalse);
      expect(loanMatches(loan, ''), isTrue);
    });
  });

  group('the pages', () {
    late NexTestHarness h;
    setUp(() async => h = await NexTestHarness.create(name: 'nex_people_'));
    tearDown(() => h.dispose());

    Widget app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: nexLightTheme(),
      home: home,
    );

    Future<NexModuleStore> seed() async {
      final store = NexModuleStore(h.services, 'lent_borrowed');
      Future<void> put(String id, String person, String dir, int amount) =>
          store.put('loan', id, {
            'person': person,
            'direction': dir,
            'type': 'money',
            'amount': amount,
            'currency': 'USD',
            'currencyDecimals': 2,
            'issued': '2026-10-01',
            'due': null,
            'note': '',
          });
      await put('a', 'Sara', 'lent', 12500);
      await put('b', 'Ali', 'borrowed', 3000);
      return store;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the overview totals what is owed and filters by search', (
      tester,
    ) async {
      final store = await seed();
      await tester.pumpWidget(app(LoansScreen(store: store)));
      await settle(tester);
      expect(find.byKey(const ValueKey('loans-summary')), findsOneWidget);
      expect(find.text('Owed to me'), findsOneWidget);
      expect(plainText('125.00 USD'), findsWidgets);
      expect(find.text('Sara'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('loans-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches that'), findsOneWidget);
      expect(find.text('Sara'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('loans-search')), 'sar');
      await tester.pumpAndSettle();
      expect(find.text('Sara'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('loans-filter-settled')));
      await tester.pumpAndSettle();
      expect(find.text('Sara'), findsNothing);
    });

    testWidgets('the people page lists both directions and opens a person', (
      tester,
    ) async {
      final store = await seed();
      await tester.pumpWidget(app(PeopleScreen(store: store)));
      await settle(tester);
      expect(plainText('Owes you 125.00 USD'), findsOneWidget);
      expect(plainText('You owe 30.00 USD'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('person-sara')));
      await settle(tester);
      expect(find.text('Sara'), findsWidgets);
      expect(find.byKey(const ValueKey('loans-summary')), findsWidgets);
    });

    testWidgets('a lent record offers three polite messages to share', (
      tester,
    ) async {
      final store = await seed();
      await tester.pumpWidget(app(LoanDetailScreen(store: store, loanId: 'a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('loan-message')));
      await tester.pumpAndSettle();
      for (final tone in ['friendly', 'plain', 'formal']) {
        expect(find.byKey(ValueKey('loan-message-$tone')), findsOneWidget);
      }
      expect(find.textContaining('Hi Sara!'), findsOneWidget);
      expect(find.textContaining('Dear Sara'), findsOneWidget);
    });

    testWidgets('a borrowed record offers no message to send', (tester) async {
      final store = await seed();
      await tester.pumpWidget(app(LoanDetailScreen(store: store, loanId: 'b')));
      await settle(tester);
      expect(find.byKey(const ValueKey('loan-message')), findsNothing);
    });
  });
}

String _inDays(int days) {
  final d = DateTime.now().add(Duration(days: days));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
