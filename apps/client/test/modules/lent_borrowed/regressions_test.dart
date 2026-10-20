import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_date_entry.dart';
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
  test('absolute entry parses the formats a person might type', () {
    expect(parseDateEntry('2026/10/15'), '2026-10-15');
    expect(parseDateEntry('2026-10-15'), '2026-10-15');
    expect(parseDateEntry('2026.10.15'), '2026-10-15');
    expect(parseDateEntry(' 2026/10/5 '), '2026-10-05');
    expect(parseDateEntry('2026/1/2'), '2026-01-02');
    expect(dateEntryText('2026-10-01'), '2026/10/01');
  });
  test('impossible and out-of-range dates are refused, not normalized', () {
    expect(parseDateEntry('2026/02/30'), isNull);
    expect(parseDateEntry('2023/02/29'), isNull);
    expect(parseDateEntry('2026/13/01'), isNull);
    expect(parseDateEntry('2026/00/10'), isNull);
    expect(parseDateEntry('2026/10/00'), isNull);
    expect(parseDateEntry(''), isNull);
    expect(parseDateEntry('next tuesday'), isNull);
    // The typed range is the calendar's own; a Jalali year such as 1405 is
    // never silently stored as the civil year 1405.
    expect(parseDateEntry('1405/07/14'), isNull);
    expect(parseDateEntry('1899/12/31'), isNull);
    expect(parseDateEntry('2101/01/01'), isNull);
  });
  test('Persian and Arabic digits parse like Latin ones', () {
    expect(parseDateEntry('۲۰۲۶/۱۰/۱۵'), '2026-10-15');
    expect(parseDateEntry('٢٠٢٦/١٠/١٥'), '2026-10-15');
  });
  test('a leap day parses and round-trips through the field text', () {
    final key = parseDateEntry('2024/2/29');
    expect(key, '2024-02-29');
    expect(parseDateEntry(dateEntryText(key!)), key);
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
