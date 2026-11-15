import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/irr_unit.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/reminder_section.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// A reminder is read on a locked screen by whoever is holding the phone.
/// The module's word for it names neither the person nor the amount unless
/// the person asked for that, record by record.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_rem_'),
  );
  tearDown(() => harness.dispose());

  Loan loan({
    bool detail = false,
    LoanKind kind = LoanKind.money,
    String person = 'Sara',
  }) => Loan(
    id: 'l1',
    direction: LoanDirection.lent,
    person: person,
    kind: kind,
    amount: kind == LoanKind.item ? 1 : 500000,
    what: kind == LoanKind.item ? 'Blue backpack' : '',
    issued: '2026-10-01',
    due: '2026-10-15',
    note: '',
    reminderDetail: detail,
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

  testWidgets('by default the reminder says nothing about the person', (
    tester,
  ) async {
    final context = await pumpHost(tester, const Locale('en'));
    final record = loan();
    final body = loanReminderBody(
      context,
      record,
      LoanMath.standing(record, const [], today: DateTime(2026, 10, 10)),
      IrrUnit.toman,
    );
    expect(body, 'A reminder you set for a loan is due. Open Nex.');
    expect(body, isNot(contains('Sara')));
    expect(body, isNot(contains('50,000')));
    expect(body, isNot(contains('toman')));
  });

  testWidgets('the Persian private line names nothing either', (tester) async {
    final context = await pumpHost(tester, const Locale('fa'));
    final record = loan();
    final body = loanReminderBody(
      context,
      record,
      LoanMath.standing(record, const [], today: DateTime(2026, 10, 10)),
      IrrUnit.toman,
    );
    expect(body, contains('یادآوری'));
    expect(body, isNot(contains('سارا')));
    expect(body, isNot(contains('تومان')));
  });

  testWidgets('when chosen, the reminder says who and how much', (
    tester,
  ) async {
    final context = await pumpHost(tester, const Locale('en'));
    final record = loan(detail: true);
    final body = loanReminderBody(
      context,
      record,
      LoanMath.standing(record, const [], today: DateTime(2026, 10, 10)),
      IrrUnit.toman,
    );
    expect(body, 'The loan with Sara is due back: 50,000 tomans.');
  });

  testWidgets('an item reminder says what is out, not a currency', (
    tester,
  ) async {
    final context = await pumpHost(tester, const Locale('fa'));
    final record = loan(detail: true, kind: LoanKind.item, person: 'سارا');
    final body = loanReminderBody(
      context,
      record,
      LoanMath.standing(record, const [], today: DateTime(2026, 10, 10)),
      IrrUnit.toman,
    );
    expect(body, contains('سارا'));
    expect(body, contains('وسیله'));
    expect(body, isNot(contains('تومان')));
  });

  testWidgets('the switch on the loan is what the reminder reads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    await store.put('loan', 'l1', {
      'direction': 'lent',
      'person': 'Sara',
      'type': 'money',
      'amount': 500000,
      'currency': 'IRR',
      'currencyDecimals': 0,
      'issued': '2026-10-01',
      'due': '2026-10-15',
      'note': '',
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoanDetailScreen(store: store, loanId: 'l1'),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('loan-reminder-detail'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      (await store.get('loan', 'l1'))?['reminderDetail'],
      isTrue,
      reason: 'the choice is kept on the record, so an edit cannot drop it',
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    // And off again, without losing anything else on the record.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final body = await store.get('loan', 'l1');
    expect(body?['reminderDetail'], isFalse);
    expect(body?['person'], 'Sara');
    expect(body?['amount'], 500000);
  });
}
