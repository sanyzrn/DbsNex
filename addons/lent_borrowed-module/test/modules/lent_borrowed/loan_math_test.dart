import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/money_format.dart';

/// The arithmetic of owing: integer rials, whole civil days, due dates
/// that cannot be bent by a DST change, and never a negative balance.
void main() {
  Loan loan({
    String id = 'l1',
    LoanDirection direction = LoanDirection.lent,
    LoanKind kind = LoanKind.money,
    int amount = 500000,
    String? due,
    String issued = '2026-10-01',
  }) => Loan(
    id: id,
    direction: direction,
    person: 'Ali',
    kind: kind,
    amount: amount,
    what: kind == LoanKind.item ? 'backpack' : '',
    issued: issued,
    due: due,
    note: '',
  );

  LoanReturn ret(
    String id,
    int amount, {
    String loanId = 'l1',
    String date = '2026-10-05',
  }) => LoanReturn(id: id, loanId: loanId, date: date, amount: amount);

  final today = DateTime(2026, 10, 12);

  group('due readings', () {
    test('no due date, and settled, say so plainly', () {
      expect(DueReading.of(null, today).status, DueStatus.none);
      expect(DueReading.of('not-a-date', today).status, DueStatus.none);
    });

    test('due today, due soon, and later', () {
      expect(DueReading.of('2026-10-12', today).status, DueStatus.today);
      expect(DueReading.of('2026-10-13', today).status, DueStatus.dueSoon);
      expect(DueReading.of('2026-10-15', today).status, DueStatus.dueSoon);
      expect(DueReading.of('2026-10-16', today).status, DueStatus.later);
      expect(DueReading.of('2026-10-16', today).days, 4);
    });

    test('overdue by whole civil days, including by exactly one', () {
      final by1 = DueReading.of('2026-10-11', today);
      expect(by1.status, DueStatus.overdue);
      expect(by1.days, 1);
      final by30 = DueReading.of('2026-09-12', today);
      expect(by30.status, DueStatus.overdue);
      expect(by30.days, 30);
    });

    test('a DST boundary cannot bend a due date', () {
      // Most of the northern hemisphere leaves DST in late October; the
      // keys are UTC midnights, so the gap is exact either way.
      final overdue = DueReading.of('2026-10-24', DateTime(2026, 10, 27));
      expect(overdue.status, DueStatus.overdue);
      expect(overdue.days, 3);
      final ahead = DueReading.of('2026-10-27', DateTime(2026, 10, 24));
      expect(ahead.status, DueStatus.dueSoon);
      expect(ahead.days, 3);
    });

    test('a leap day is just a day', () {
      final reading = DueReading.of('2024-02-28', DateTime(2024, 3, 1));
      expect(reading.status, DueStatus.overdue);
      expect(reading.days, 2);
    });
  });

  group('standing', () {
    test('nothing returned: the whole amount is out', () {
      final s = LoanMath.standing(
        loan(due: '2026-10-15'),
        const [],
        today: today,
      );
      expect(s.outstanding, 500000);
      expect(s.returned, 0);
      expect(s.settled, isFalse);
    });

    test('a partial return leaves the rest, and history', () {
      final s = LoanMath.standing(loan(), [ret('r1', 200000)], today: today);
      expect(s.outstanding, 300000);
      expect(s.returned, 200000);
      expect(s.settled, isFalse);
    });

    test('fully returned reads as settled', () {
      final s = LoanMath.standing(loan(due: '2026-10-10'), [
        ret('r1', 200000),
        ret('r2', 300000),
      ], today: today);
      expect(s.outstanding, 0);
      expect(s.settled, isTrue);
      expect(s.due.status, DueStatus.settled);
    });

    test('corrupt over-returned history cannot go negative', () {
      final s = LoanMath.standing(loan(amount: 100000), [
        ret('r1', 100000),
        ret('r2', 50000),
      ], today: today);
      expect(s.outstanding, 0);
      expect(s.settled, isTrue);
    });

    test('another loan’s returns do not count', () {
      final s = LoanMath.standing(loan(), [
        ret('r9', 400000, loanId: 'other'),
      ], today: today);
      expect(s.outstanding, 500000);
    });

    test('items count in quantity, not rials', () {
      final s = LoanMath.standing(loan(kind: LoanKind.item, amount: 3), [
        ret('r1', 1),
      ], today: today);
      expect(s.outstanding, 2);
      expect(s.returned, 1);
    });

    test('very large amounts stay exact', () {
      final s = LoanMath.standing(loan(amount: 1000000000000), [
        ret('r1', 999999999999),
      ], today: today);
      expect(s.outstanding, 1);
    });

    test('a zero-amount record reads as settled, not as a crash', () {
      final s = LoanMath.standing(loan(amount: 0), const [], today: today);
      expect(s.settled, isTrue);
      expect(s.outstanding, 0);
    });
  });

  group('the return guard', () {
    test('zero and negative amounts are refused', () {
      expect(LoanMath.returnError(loan(), const [], 0), 'zero');
      expect(LoanMath.returnError(loan(), const [], -5), 'zero');
    });

    test('over-repayment is refused at exactly one over', () {
      expect(LoanMath.returnError(loan(), [ret('r1', 200000)], 300001), 'over');
      expect(LoanMath.returnError(loan(), [ret('r1', 200000)], 300000), isNull);
      expect(LoanMath.returnError(loan(), const [], 1), isNull);
    });
  });

  group('the edit guard', () {
    test('a new total below what came back is refused', () {
      expect(
        LoanMath.totalError([ret('r1', 200000)], 199999),
        'below-returned',
      );
      expect(LoanMath.totalError([ret('r1', 200000)], 200000), isNull);
      expect(LoanMath.totalError([ret('r1', 200000)], 300000), isNull);
    });
  });

  group('money formatting', () {
    test('grouped thousands, English and Persian', () {
      expect(formatRials(500000, false), '500,000');
      expect(formatRials(1234567, false), '1,234,567');
      expect(formatRials(500000, true), '۵۰۰٬۰۰۰');
      expect(formatRials(0, true), '۰');
    });
  });

  group('civil date keys', () {
    test('zero-padded', () {
      expect(civilDateKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });
}
