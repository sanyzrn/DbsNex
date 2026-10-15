import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_dates.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';

void main() {
  Loan loan(String? due) => Loan(
    id: 'l',
    direction: LoanDirection.lent,
    person: 'Ali',
    kind: LoanKind.money,
    amount: 10000,
    what: '',
    issued: '2026-10-01',
    due: due,
    note: '',
    currency: 'USD',
  );
  test(
    'editing a historical loan reads due relative to today and preserves it',
    () {
      final editor = LoanDates(
        DateTime(2026, 10, 12, 23, 59),
        loan('2026-10-15'),
      );
      expect(editor.issueOffset, 11);
      expect(editor.dueOffset, 3);
      expect(editor.issued(11), '2026-10-01');
      expect(editor.due(3), '2026-10-15');
      expect(editor.due(7), '2026-10-19');
    },
  );
  test('overdue edits retain negative offsets and no date stays null', () {
    final overdue = LoanDates(DateTime(2026, 10, 12), loan('2026-10-11'));
    expect(overdue.dueOffset, -1);
    expect(overdue.due(-1), '2026-10-11');
    expect(LoanDates(DateTime(2026, 10, 12), loan(null)).dueOffset, isNull);
    expect(overdue.due(null), isNull);
    expect(overdue.due(0), '2026-10-12');
  });
  test('civil shifts span leap-day, year and DST boundaries exactly', () {
    expect(shiftCivilDate(DateTime(2024, 2, 28, 23, 59), 1), '2024-02-29');
    expect(shiftCivilDate(DateTime(2026, 12, 31), 1), '2027-01-01');
    expect(shiftCivilDate(DateTime(2026, 10, 24, 23, 59), 2), '2026-10-26');
    expect(
      DueReading.of('2026-02-30', DateTime(2026, 3, 2)).status,
      DueStatus.none,
    );
  });
  test(
    'legacy amounts stay whole rials; foreign repayments use minor units',
    () {
      final old = Loan.fromBody('legacy', {'amount': 500000});
      expect(old.currency, 'IRR');
      expect(old.digits, 0);
      expect(old.amount, 500000);
      final usd = Loan.fromBody('l', loan(null).toJson());
      expect(usd.currency, 'USD');
      expect(usd.digits, 2);
      final payments = [
        const LoanReturn(
          id: 'r',
          loanId: 'l',
          date: '2026-10-12',
          amount: 1234,
        ),
      ];
      expect(LoanMath.standing(usd, payments).outstanding, 8766);
      expect(LoanMath.returnError(usd, payments, 8767), 'over');
    },
  );
  test('several huge returns cannot wrap an integer balance negative', () {
    final model = Loan.fromBody('l', {'amount': 9007199254740991});
    final payments = List.generate(
      2000,
      (i) =>
          LoanReturn(id: '$i', loanId: 'l', date: '', amount: 9007199254740991),
    );
    expect(LoanMath.standing(model, payments).outstanding, 0);
  });
}
