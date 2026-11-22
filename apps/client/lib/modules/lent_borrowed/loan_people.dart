import 'loan_math.dart';
import 'loan_model.dart';
import 'money_format.dart';

/// What the same name means across records: one person, however it was
/// written. Case, spacing, Arabic yeh/kaf and the half-space are folded; no
/// two different names ever meet.
String personKey(String name) {
  final folded = name
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('‌', ' ')
      .replaceAll(RegExp(r'[ً-ٟـ]'), '')
      .toLowerCase()
      .trim();
  return folded.replaceAll(RegExp(r'\s+'), ' ');
}

/// One currency's total of what is still out.
class CurrencyTotal {
  const CurrencyTotal(this.currency, this.digits, this.minor)
    : _exactMinor = null;

  CurrencyTotal._fromExact(this.currency, this.digits, BigInt exact)
    : _exactMinor = exact,
      minor = _boundedMinor(exact);

  static final _limit = BigInt.from(maxMoney);

  static int _boundedMinor(BigInt value) {
    if (value > _limit) return maxMoney;
    if (value < -_limit) return -maxMoney;
    return value.toInt();
  }

  final BigInt? _exactMinor;
  BigInt get _amount => _exactMinor ?? BigInt.from(minor);

  final String currency;
  final int digits;
  final int minor;
}

/// What a set of records adds up to: money per currency — never summed across
/// currencies — the count of items still out, and how many are overdue.
class LoanSummary {
  const LoanSummary({
    required this.money,
    required this.itemsOut,
    required this.open,
    required this.overdue,
  });

  factory LoanSummary.of(Iterable<Loan> loans, List<LoanReturn> returns) =>
      LoanSummary.ofBucketed(loans, LoanMath.returnsByLoan(returns));

  /// The same summary when the returns are already bucketed by loan: the
  /// People page answers once per person, and re-bucketing every return for
  /// each of them was the one repeated piece of work on that page.
  factory LoanSummary.ofBucketed(
    Iterable<Loan> loans,
    Map<String, List<LoanReturn>> returnsByLoan,
  ) {
    final totals = <String, (int, BigInt)>{};
    var items = 0, open = 0, overdue = 0;
    final bucketed = returnsByLoan;
    for (final loan in loans) {
      final standing = LoanMath.standing(loan, bucketed[loan.id] ?? const []);
      if (standing.settled) continue;
      open++;
      if (standing.due.status == DueStatus.overdue) overdue++;
      if (loan.kind == LoanKind.item) {
        items++;
        continue;
      }
      final key = '${loan.currency}/${loan.digits}';
      final held = totals[key];
      totals[key] = (
        loan.digits,
        (held?.$2 ?? BigInt.zero) + BigInt.from(standing.outstanding),
      );
    }
    final ordered = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return LoanSummary(
      money: [
        for (final entry in ordered)
          CurrencyTotal._fromExact(
            entry.key.split('/').first,
            entry.value.$1,
            entry.value.$2,
          ),
      ],
      itemsOut: items,
      open: open,
      overdue: overdue,
    );
  }

  /// What the two directions leave between you, per currency — only where
  /// both sides have money in that currency, since otherwise the single
  /// direction already answers. Positive means they owe you.
  static List<CurrencyTotal> net(LoanSummary owedToMe, LoanSummary iOwe) {
    final mine = _byCurrency(owedToMe.money);
    final theirs = _byCurrency(iOwe.money);
    final out = <CurrencyTotal>[];
    for (final entry in mine.entries) {
      final owing = theirs[entry.key];
      if (owing == null) continue;
      final held = entry.value;
      final digits = held.digits > owing.digits ? held.digits : owing.digits;
      final difference = _rescale(held, digits) - _rescale(owing, digits);
      if (difference != BigInt.zero) {
        out.add(CurrencyTotal._fromExact(entry.key, digits, difference));
      }
    }
    return out;
  }

  static Map<String, CurrencyTotal> _byCurrency(List<CurrencyTotal> totals) {
    final byCurrency = <String, CurrencyTotal>{};
    for (final total in totals) {
      byCurrency.update(total.currency, (previous) {
        final digits = previous.digits > total.digits
            ? previous.digits
            : total.digits;
        return CurrencyTotal._fromExact(
          total.currency,
          digits,
          _rescale(previous, digits) + _rescale(total, digits),
        );
      }, ifAbsent: () => total);
    }
    return byCurrency;
  }

  static BigInt _rescale(CurrencyTotal total, int digits) =>
      total._amount * BigInt.from(moneyFactor(digits - total.digits));

  final List<CurrencyTotal> money;
  final int itemsOut;
  final int open;
  final int overdue;

  bool get isEmpty => open == 0;
}

/// One person across every record: both directions, kept apart.
class PersonLedger {
  const PersonLedger({
    required this.key,
    required this.name,
    required this.loans,
    required this.owedToMe,
    required this.iOwe,
  });

  final String key;
  final String name;
  final List<Loan> loans;
  final LoanSummary owedToMe;
  final LoanSummary iOwe;

  /// Anything still open either way.
  bool get open => !owedToMe.isEmpty || !iOwe.isEmpty;
}

/// Everyone who appears in [loans], open balances first, then by name.
List<PersonLedger> peopleOf(List<Loan> loans, List<LoanReturn> returns) {
  final groups = <String, List<Loan>>{};
  for (final loan in loans) {
    groups.putIfAbsent(personKey(loan.person), () => []).add(loan);
  }
  // One pass over the returns for the whole page, not one per person.
  final bucketed = LoanMath.returnsByLoan(returns);
  final people = [
    for (final MapEntry(:key, value: mine) in groups.entries)
      PersonLedger(
        key: key,
        name: mine.first.person.trim(),
        loans: mine,
        owedToMe: LoanSummary.ofBucketed(
          mine.where((l) => l.direction == LoanDirection.lent),
          bucketed,
        ),
        iOwe: LoanSummary.ofBucketed(
          mine.where((l) => l.direction == LoanDirection.borrowed),
          bucketed,
        ),
      ),
  ];
  people.sort((a, b) {
    if (a.open != b.open) return a.open ? -1 : 1;
    return a.key.compareTo(b.key);
  });
  return people;
}
