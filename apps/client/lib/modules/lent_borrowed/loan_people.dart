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
  const CurrencyTotal(this.currency, this.digits, this.minor);

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

  factory LoanSummary.of(Iterable<Loan> loans, List<LoanReturn> returns) {
    final totals = <String, (int, BigInt)>{};
    var items = 0, open = 0, overdue = 0;
    for (final loan in loans) {
      final standing = LoanMath.standing(loan, returns);
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
          CurrencyTotal(
            entry.key.split('/').first,
            entry.value.$1,
            entry.value.$2 > BigInt.from(maxMoney)
                ? maxMoney
                : entry.value.$2.toInt(),
          ),
      ],
      itemsOut: items,
      open: open,
      overdue: overdue,
    );
  }

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
  final people = [
    for (final MapEntry(:key, value: mine) in groups.entries)
      PersonLedger(
        key: key,
        name: mine.first.person.trim(),
        loans: mine,
        owedToMe: LoanSummary.of(
          mine.where((l) => l.direction == LoanDirection.lent),
          returns,
        ),
        iOwe: LoanSummary.of(
          mine.where((l) => l.direction == LoanDirection.borrowed),
          returns,
        ),
      ),
  ];
  people.sort((a, b) {
    if (a.open != b.open) return a.open ? -1 : 1;
    return a.key.compareTo(b.key);
  });
  return people;
}
