import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loan_shared.dart';

/// Lent & borrowed in the shape every module shares (docs/18, 2.8.4): due
/// dates with what is still out — in for lent, out for borrowed — and a line
/// about each record, money kept private.
void main() {
  Loan loan(String id, Map<String, Object?> body) => Loan.fromBody(id, {
    'v': 2,
    'currency': 'IRR',
    'type': 'money',
    'issued': '2026-11-01',
    ...body,
  });

  test('due dates, signed by direction, what is left after returns', () {
    final loans = [
      loan('a', {
        'direction': 'lent',
        'person': 'Sara',
        'amount': 5000000,
        'due': '2026-11-20',
      }),
      loan('b', {
        'direction': 'borrowed',
        'person': 'Reza',
        'amount': 2000000,
        'due': '2026-11-25',
      }),
      loan('c', {
        'direction': 'lent',
        'person': 'Ali',
        'type': 'item',
        'what': 'Drill',
        'amount': 1,
        'due': '2026-11-22',
      }),
      loan('d', {'direction': 'lent', 'person': 'No date', 'amount': 1}),
      loan('e', {
        'direction': 'lent',
        'person': 'Later',
        'amount': 1,
        'due': '2027-01-05',
      }),
    ];
    final returns = [
      LoanReturn.fromBody('r1', {
        'loan': 'a',
        'date': '2026-11-10',
        'amount': 1500000,
      }),
      LoanReturn.fromBody('r2', {
        'loan': 'b',
        'date': '2026-11-10',
        'amount': 2000000,
      }),
    ];
    final dues = LoanShared(
      loans,
      returns,
    ).duesBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 30, 23, 59));
    expect([for (final d in dues) d.recordId], ['a', 'c', 'b']);
    expect(dues[0].amountRial, 3500000);
    expect(dues[0].kind, 'loan-lent');
    expect(dues[0].done, isFalse);
    expect(dues[1].title, 'Ali · Drill');
    expect(dues[1].amountRial, isNull, reason: 'a thing, not money');
    expect(dues[2].amountRial, 0);
    expect(dues[2].done, isTrue, reason: 'paid back in full');
    expect(dues.every((d) => d.private), isTrue);
  });

  test('a line about a loan or a split; nothing for the card book', () {
    ModuleRecord record(String kind, Map<String, Object?> body) => ModuleRecord(
      module: 'lent_borrowed',
      kind: kind,
      id: 'x',
      body: body,
      updatedAt: DateTime(2026),
    );
    final line = LoanShared.summarize(
      record('loan', {
        'direction': 'lent',
        'person': 'سارا',
        'type': 'money',
        'amount': 1,
        'note': 'بلیت قطار',
      }),
    )!;
    expect(
      (line.title, line.detail, line.private),
      ('سارا', 'بلیت قطار', true),
    );
    expect(
      LoanShared.summarize(
        record('split', {
          'title': 'سفر شمال',
          'people': ['علی', 'سارا'],
        }),
      )!.title,
      'سفر شمال',
    );
    expect(
      LoanShared.summarize(record('card', {'person': 'Ali', 'card': '6037'})),
      isNull,
    );
    expect(LoanShared.summarize(record('settings', {})), isNull);
  });
}
