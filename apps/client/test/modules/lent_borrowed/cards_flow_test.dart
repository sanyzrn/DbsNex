import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/cards_screen.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';

import '../../support/nex_harness.dart';

/// The card book, end to end: add a card with an IBAN, see it grouped, and
/// find it again inside a message to that person — with copy one tap away.
void main() {
  Future<NexTestHarness> harness() async {
    final h = await NexTestHarness.create(name: 'lent_cards_');
    addTearDown(h.dispose);
    return h;
  }

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('a card with an IBAN is saved, grouped and listed', (
    tester,
  ) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await tester.pumpWidget(app(CardsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Cards & IBANs'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cards-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('card-field-person')),
      'Sara',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-field-holder')),
      'Sara A.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-field-number')),
      '6037 9912 3456 7893',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-field-iban')),
      'IR820540102680020817909002',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Bank Melli Iran'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('card-save')));
    await tester.pumpAndSettle();

    final saved = (await store.list('card')).single;
    expect(saved.body['person'], 'Sara');
    expect(saved.body['card'], '6037991234567893');
    expect(saved.body['iban'], 'IR820540102680020817909002');
    expect(find.text('6037 9912 3456 7893'), findsOneWidget);
    expect(find.text('IR82 0540 1026 8002 0817 9090 02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a broken card is refused with its own words', (tester) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await tester.pumpWidget(app(CardsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cards-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('card-field-person')),
      'Ali',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-field-number')),
      '6037 9912 3456 7890',
    );
    await tester.tap(find.byKey(const ValueKey('card-save')));
    await tester.pumpAndSettle();
    expect(find.text('That card number does not check out.'), findsWidgets);
    expect(await store.list('card'), isEmpty);
  });

  testWidgets('a message to a person carries the card they gave', (
    tester,
  ) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('card', 'sara', {
      'v': 1,
      'person': 'Sara',
      'holder': 'Sara A.',
      'card': '6037991234567893',
      'iban': 'IR820540102680020817909002',
    });
    await store.put('loan', 'l1', {
      'v': 2,
      'direction': 'lent',
      'person': 'Sara',
      'type': 'money',
      'amount': 500000,
      'issued': '2026-10-01',
      'due': null,
    });
    await tester.pumpWidget(app(PeopleScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('people-message-sara')));
    await tester.pumpAndSettle();

    expect(find.textContaining('I owe you'), findsNothing);
    expect(find.textContaining('You owe me'), findsOneWidget);
    expect(find.textContaining('6037 9912 3456 7893'), findsOneWidget);
    expect(
      find.textContaining('IR82 0540 1026 8002 0817 9090 02'),
      findsOneWidget,
    );
    expect(find.textContaining('Sara A.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a card can be undone', (tester) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('card', 'sara', {
      'v': 1,
      'person': 'Sara',
      'holder': '',
      'card': '6037991234567893',
      'iban': '',
    });
    await tester.pumpWidget(app(CardsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-delete-sara')));
    await tester.pumpAndSettle();
    expect(await store.list('card'), isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await store.list('card'), hasLength(1));
  });
}
