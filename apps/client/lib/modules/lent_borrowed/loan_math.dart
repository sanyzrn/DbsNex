import 'loan_model.dart';
import 'loan_dates.dart';

/// How a due date reads today. The days are whole civil days, so no DST
/// shift can bend a deadline.
class DueReading {
  const DueReading._(this.status, this.days);

  final DueStatus status;

  /// For [DueStatus.overdue], how many whole days late; for
  /// [DueStatus.dueSoon] and [DueStatus.later], how many days remain.
  /// Zero for the rest.
  final int days;

  static const none = DueReading._(DueStatus.none, 0);
  static const settled = DueReading._(DueStatus.settled, 0);
  static const today = DueReading._(DueStatus.today, 0);

  /// How [due] reads against [now]. The day count runs from the due date
  /// to today, so a positive gap is time already past.
  static DueReading of(String? due, DateTime now) {
    if (due == null) return none;
    final days = civilDaysBetween(due, civilDateKey(now));
    if (days == null) return none;
    if (days > 0) return DueReading._(DueStatus.overdue, days);
    if (days == 0) return today;
    final until = -days;
    if (until <= 3) return DueReading._(DueStatus.dueSoon, until);
    return DueReading._(DueStatus.later, until);
  }
}

enum DueStatus { none, settled, later, dueSoon, today, overdue }

/// Where a loan stands: what is still out, and how its due date reads.
/// Integer arithmetic only; money never becomes a double.
class LoanStanding {
  const LoanStanding({
    required this.outstanding,
    required this.returned,
    required this.due,
  });

  /// What is still owed — the loan minus every recorded return, never
  /// below zero.
  final int outstanding;

  /// Everything that has come back so far.
  final int returned;

  final DueReading due;

  bool get settled => outstanding == 0;
}

/// The arithmetic of lending and borrowing, kept boring on purpose.
class LoanMath {
  static int _sum(Iterable<LoanReturn> returns) {
    final value = returns.fold(
      BigInt.zero,
      (sum, r) => sum + BigInt.from(r.amount < 0 ? 0 : r.amount),
    );
    return value > BigInt.from(9007199254740991)
        ? 9007199254740991
        : value.toInt();
  }

  /// The standing of [loan] against [returns]: outstanding money or
  /// quantity, clamped at zero so corrupt history cannot invent a debt
  /// running backwards.
  static LoanStanding standing(
    Loan loan,
    List<LoanReturn> returns, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final mine = returns.where((r) => r.loanId == loan.id).toList();
    final returned = _sum(mine);
    final outstanding = loan.amount - returned;
    final settled = outstanding <= 0;
    return LoanStanding(
      outstanding: outstanding < 0 ? 0 : outstanding,
      returned: returned,
      due: settled ? DueReading.settled : DueReading.of(loan.due, now),
    );
  }

  /// Whether a new return of [amount] is allowed: at least 1, and never
  /// more than what is outstanding. Over-repayment is refused here before
  /// it can reach the store.
  static String? returnError(Loan loan, List<LoanReturn> returns, int amount) {
    final outstanding = standing(loan, returns).outstanding;
    if (amount <= 0) return 'zero';
    if (amount > outstanding) return 'over';
    return null;
  }

  /// Whether editing a loan's total to [newAmount] is allowed: the part
  /// already returned cannot exceed it.
  static String? totalError(List<LoanReturn> returns, int newAmount) {
    final returned = _sum(returns);
    return returned > newAmount ? 'below-returned' : null;
  }
}
