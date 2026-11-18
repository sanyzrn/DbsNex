import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/expenses_summary.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart'
    show ModuleRecord, NexModuleMonth;

/// The recurring payments read as dates: the day they fall due each month,
/// in the calendar they were set in, month ends included — and whether the
/// month is already written down.
ExpenseTemplate tpl({
  String id = 'tpl-rent',
  int day = 5,
  String calendar = 'gregorian',
  String type = 'expense',
  int amountRial = 120000000,
  String label = 'Rent',
}) => ExpenseTemplate(
  id: id,
  label: label,
  type: type,
  amountRial: amountRial,
  categoryId: 'cat-rent',
  day: day,
  calendar: calendar,
);

ExpenseTx logged(DateTime day, {String id = 'tx-1'}) => ExpenseTx(
  id: id,
  type: 'expense',
  amountRial: 120000000,
  date: day,
  templateId: 'tpl-rent',
  period: monthStartIso(NexModuleMonth.of(day, solar: false)),
);

void main() {
  test('a monthly payment falls on its day, once per month in range', () {
    final schedule = ExpenseSchedule(templates: [tpl()], txs: const []);
    final dues = schedule.duesBetween(
      DateTime(2026, 9, 15),
      DateTime(2026, 11, 15),
    );
    expect(dues.map((d) => d.at), [
      DateTime(2026, 10, 5),
      DateTime(2026, 11, 5),
    ]);
    expect(dues.first.amountRial, -120000000);
    expect(dues.first.kind, 'expense-recurring');
    expect(dues.first.recordKind, 'tpl');
    expect(dues.first.recordId, 'tpl-rent');
    expect(dues.first.private, isTrue);
    expect(dues.first.title, 'Rent');
  });

  test('the same rent in the same month is the same item next time', () {
    final schedule = ExpenseSchedule(templates: [tpl()], txs: const []);
    final first = schedule.duesBetween(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31),
    );
    final second = ExpenseSchedule(
      templates: [tpl()],
      txs: const [],
    ).duesBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    expect(first.single.id, second.single.id);
    expect(first.single.id, contains('2026-10-01'));
  });

  test('a short month clamps the day instead of skipping the payment', () {
    final schedule = ExpenseSchedule(templates: [tpl(day: 31)], txs: const []);
    final dues = schedule.duesBetween(
      DateTime(2027, 2, 1),
      DateTime(2027, 2, 28),
    );
    expect(dues.single.at, DateTime(2027, 2, 28));
  });

  test('Esfand 29 and 30, and a day past the month’s end', () {
    final leap = NexModuleMonth(true, 1403, 12);
    expect(leap.days, 30, reason: '1403 is a Jalali leap year');
    final schedule = ExpenseSchedule(
      templates: [tpl(day: 31, calendar: 'jalali')],
      txs: const [],
    );
    final dues = schedule.duesBetween(leap.first, leap.dayAt(30));
    expect(dues.single.at, leap.dayAt(30));
  });

  test(
    'a Jalali day is counted in the Jalali month, not the Gregorian one',
    () {
      // Aban 1405 starts on 23 October 2026.
      final schedule = ExpenseSchedule(
        templates: [tpl(day: 5, calendar: 'jalali')],
        txs: const [],
      );
      final dues = schedule.duesBetween(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
      );
      expect(dues.single.at, DateTime(2026, 10, 27));
    },
  );

  test('a month already written down is done, not offered again', () {
    final schedule = ExpenseSchedule(
      templates: [tpl()],
      txs: [logged(DateTime(2026, 10, 5))],
    );
    final dues = schedule.duesBetween(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31),
    );
    expect(dues.single.done, isTrue);
    expect(
      ExpenseSchedule(
        templates: [tpl()],
        txs: const [],
      ).duesBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 31)).single.done,
      isFalse,
    );
  });

  test('income falls due positively, and a plain template never falls due', () {
    final schedule = ExpenseSchedule(
      templates: [tpl(type: 'income', amountRial: 5000000)],
      txs: const [],
    );
    expect(
      schedule
          .duesBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 31))
          .single
          .amountRial,
      5000000,
    );
    expect(
      ExpenseSchedule(
        templates: const [],
        txs: const [],
      ).duesBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      isEmpty,
    );
  });

  test('the line about a record names it without exposing the amount', () {
    final summary = summarize(
      ModuleRecord(
        module: 'expenses',
        kind: 'tx',
        id: 'tx-1',
        body: {
          'type': 'expense',
          'amountRial': 1250000,
          'date': '2026-10-14T12:00:00',
          'note': 'Weekly shop',
          'category': 'cat-groceries',
        },
        updatedAt: DateTime(2026, 10, 14),
      ),
    )!;
    expect(summary.title, 'Weekly shop');
    expect(summary.detail, contains('Expense'));
    expect(summary.detail, contains('125,000 tomans'));
    expect(summary.private, isTrue);
  });

  test('a record with nothing to say is kept out', () {
    expect(
      summarize(
        ModuleRecord(
          module: 'expenses',
          kind: 'tx',
          id: 'x',
          body: const {},
          updatedAt: DateTime(2026),
        ),
      ),
      isNull,
    );
  });
}
