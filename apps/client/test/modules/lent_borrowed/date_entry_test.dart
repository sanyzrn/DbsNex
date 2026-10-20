import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loan_date_entry.dart';
import 'package:nex_client/modules/lent_borrowed/loan_dates.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';

import '../../support/nex_harness.dart';
import '../../support/more_details.dart';
import 'loans_test_tools.dart';

/// The shared Jalali/civil date entry: a calendar button beside every date
/// the person writes, presets that still work in one tap, and the picked
/// date landing in the field and in storage exactly.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_date_'),
  );
  tearDown(() => harness.dispose());

  String todayKey() => civilDateKey(DateTime.now());

  String dueFieldText(WidgetTester tester) => tester
      .widget<TextField>(
        find
            .descendant(
              // The key on the TextField itself has no TextField beneath it;
              // the entry wrapper is the ancestor that holds the field.
              of: find.byKey(const ValueKey('loan-due-date-entry')),
              matching: find.byType(TextField),
            )
            .first,
      )
      .controller!
      .text;

  testWidgets('a calendar button sits beside the issue and due fields', (
    tester,
  ) async {
    await pumpLoansScreen(tester, harness: harness);
    await tester.tap(find.byKey(const ValueKey('loans-new')));
    await tester.pumpAndSettle();
    await openMoreDetails(tester, 'loan-more-toggle');
    expect(
      find.byIcon(Icons.calendar_month_outlined),
      findsNWidgets(2),
      reason: 'one for the issue date, one for the due date',
    );
    // The issue field starts filled, so its hint stays hidden (an opacity
    // it animates to); only the empty due field offers the format hint.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('loan-due-date-entry')),
        matching: find.text('YYYY/MM/DD'),
      ),
      findsOneWidget,
    );
    expect(dueFieldText(tester), '');
  });

  testWidgets('the issue date starts at today and the chip restores it', (
    tester,
  ) async {
    await pumpLoansScreen(tester, harness: harness);
    await tester.tap(find.byKey(const ValueKey('loans-new')));
    await tester.pumpAndSettle();
    await openMoreDetails(tester, 'loan-more-toggle');
    final field = find.descendant(
      of: find.byKey(const ValueKey('loan-issue-date-entry')),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(field).controller!.text,
      dateEntryText(todayKey()),
    );
    await tester.enterText(field, '');
    await tester.pump();
    final today = find.byKey(const ValueKey('loan-issue-today'));
    await tester.ensureVisible(today);
    await tester.tap(today);
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.text,
      dateEntryText(todayKey()),
    );
  });

  testWidgets('a typed date outside the range is refused, not guessed', (
    tester,
  ) async {
    final store = await pumpLoansScreen(tester, harness: harness);
    await tester.tap(find.byKey(const ValueKey('loans-new')));
    await tester.pumpAndSettle();
    await openMoreDetails(tester, 'loan-more-toggle');
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-person')),
      'Ali',
    );
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-amount')),
      '100000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-issued')),
      '1405/07/14',
    );
    final save = find.byKey(const ValueKey('loan-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Write the date as year/month/day'),
      findsOneWidget,
    );
    expect(await store.list('loan'), isEmpty);
  });

  group('picking a date on the Jalali calendar', () {
    testWidgets('a Persian reader picks a due day and it saves exactly', (
      tester,
    ) async {
      final store = await pumpLoansScreen(
        tester,
        harness: harness,
        locale: const Locale('fa'),
      );
      await tester.tap(find.byKey(const ValueKey('loans-new')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'loan-more-toggle');
      expect(find.byIcon(Icons.calendar_month_outlined), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-person')),
        'علی',
      );
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '12000',
      );
      // An issue date far in the past, so any day the calendar offers is a
      // valid deadline for it.
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-issued')),
        '1900/01/01',
      );
      final calendar = find.descendant(
        of: find.byKey(const ValueKey('loan-due-date-entry')),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(calendar);
      await tester.tap(calendar);
      await tester.pumpAndSettle();
      expect(find.byType(NexAlertDialog), findsOneWidget);
      final day = find.text('۲۰');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pump();
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      final picked = dueFieldText(tester);
      expect(parseDateEntry(picked), isNotNull);
      expect(find.byType(NexAlertDialog), findsNothing);

      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await settleLoans(tester);
      final body = (await store.list('loan')).first.body;
      expect(body['issued'], '1900-01-01');
      expect(body['due'], parseDateEntry(picked));
      expect(body['person'], 'علی');
    });
  });

  group('the return sheet', () {
    testWidgets('its date starts at today, with a calendar beside it', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const ValueKey('return-date-entry')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        dateEntryText(todayKey()),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('return-date-entry')),
          matching: find.byIcon(Icons.calendar_month_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a return dated in the future is refused', (tester) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-date')),
        shiftCivilDate(DateTime.now(), 1),
      );
      final save = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('A return cannot be dated in the future'),
        findsOneWidget,
      );
      expect(await store.list('return'), isEmpty);
    });

    testWidgets('a return dated before the loan is refused', (tester) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-date')),
        shiftCivilDate(DateTime.now(), -1),
      );
      final save = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('A return cannot be dated before the loan date'),
        findsOneWidget,
      );
      expect(await store.list('return'), isEmpty);
    });

    testWidgets('the Today chip brings the date back and the return saves', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '50000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('return-field-date')),
        'not a date',
      );
      await tester.tap(find.byKey(const ValueKey('return-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Write the date as year/month/day'),
        findsOneWidget,
      );
      final today = find.byKey(const ValueKey('return-date-today'));
      await tester.ensureVisible(today);
      await tester.tap(today);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('return-save')));
      await settleLoans(tester);
      final returns = await store.list('return');
      expect(returns, hasLength(1));
      expect(returns.first.body['date'], todayKey());
      expect(returns.first.body['amount'], 50000);
    });
  });

  testWidgets('the detail panel shows both dates on the shared label', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = await pumpLoansScreen(tester, harness: harness);
    await store.put('loan', 'l1', {
      'person': 'Ali',
      'direction': 'lent',
      'type': 'money',
      'amount': 100000,
      'issued': civilDateKey(now),
      'due': shiftCivilDate(now, 7),
      'note': '',
    });
    await settleLoans(tester);
    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    expect(
      find.text('Issued ${dateEntryText(civilDateKey(now))}'),
      findsOneWidget,
    );
    expect(
      find.text('Due in 7 days · ${dateEntryText(shiftCivilDate(now, 7))}'),
      findsOneWidget,
    );
  });
}
