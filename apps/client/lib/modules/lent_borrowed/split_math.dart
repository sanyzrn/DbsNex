import 'loan_model.dart';
import 'loan_people.dart';
import 'money_format.dart';
import 'split_model.dart';

/// What one person's share of a single cost is, before the payer is
/// credited.
Map<String, int> splitParts(SplitCost cost) {
  final names = cost.parts.keys.toList()..sort();
  if (names.isEmpty || cost.amount <= 0) return const {};
  if (cost.mode == SplitMode.amounts) {
    if (cost.parts.values.fold(0, (a, b) => a + b) != cost.amount) {
      // A broken cost contributes nothing rather than inventing money.
      return const {};
    }
    return {
      for (final name in names) name: cost.parts[name]!.clamp(0, cost.amount),
    };
  }
  // A cost in whole tomans is shared in whole tomans (2.8.4): divided to the
  // rial, 100,000 tomans among three read as 33,333.4 tomans — a tenth no
  // one can pay. The leftover tomans go one each, as the rials did. Once:
  // a toman, never a further power of ten.
  final unit = cost.amount % _toman == 0 ? _toman : 1;
  final inUnits = _divide(cost.amount ~/ unit, cost, names);
  return {
    for (final MapEntry(:key, :value) in inUnits.entries) key: value * unit,
  };
}

/// Ten rials: a toman.
const _toman = 10;

/// [amount] divided among [names] the way [cost] says, every unit of it
/// given to someone.
Map<String, int> _divide(int amount, SplitCost cost, List<String> names) {
  if (cost.mode == SplitMode.equal) {
    final base = amount ~/ names.length;
    var rest = amount % names.length;
    return {for (final name in names) name: base + (rest-- > 0 ? 1 : 0)};
  }
  final weights = {
    for (final name in names) name: cost.parts[name]!.clamp(1, maxMoney),
  };
  final totalWeight = weights.values.fold(0, (a, b) => a + b);
  final base = <String, int>{};
  final remainders = <(String, int)>[];
  for (final name in names) {
    final product = BigInt.from(amount) * BigInt.from(weights[name]!);
    final divisor = BigInt.from(totalWeight);
    base[name] = (product ~/ divisor).toInt();
    remainders.add((name, (product % divisor).toInt()));
  }
  var rest = amount - base.values.fold(0, (a, b) => a + b);
  remainders.sort((a, b) {
    final byRemainder = b.$2.compareTo(a.$2);
    return byRemainder != 0 ? byRemainder : a.$1.compareTo(b.$1);
  });
  for (final (name, _) in remainders) {
    if (rest <= 0) break;
    base[name] = base[name]! + 1;
    rest--;
  }
  return base;
}

/// One person's net position in a split: positive means the group owes them,
/// negative means they owe the group.
class SplitBalance {
  const SplitBalance(this.person, this.net);

  final String person;
  final int net;

  bool get isEven => net == 0;
  bool get receives => net > 0;
}

/// Everyone's net position, including people whose costs cancel out to zero
/// (so the page can say they are even instead of hiding them).
List<SplitBalance> splitBalances(LoanSplit split) {
  final net = <String, int>{for (final person in split.people) person: 0};
  for (final cost in split.costs) {
    net[cost.payer] = (net[cost.payer] ?? 0) + cost.amount;
    for (final MapEntry(:key, :value) in splitParts(cost).entries) {
      net[key] = (net[key] ?? 0) - value;
    }
  }
  final names = net.keys.toList()..sort();
  return [for (final name in names) SplitBalance(name, net[name] ?? 0)];
}

/// One payment that makes the group even: [from] pays [to] [amount].
class SplitTransfer {
  const SplitTransfer({
    required this.from,
    required this.to,
    required this.amount,
  });

  final String from;
  final String to;
  final int amount;

  bool involves(String person) => from == person || to == person;
}

/// The payments that settle [split].
///
/// The largest debtor pays the largest creditor each time, which never
/// leaves anyone in the middle and produces at most one transfer per person
/// minus one — the standard "min cash flow" reading of "fewest transfers".
/// It is deterministic (ties break by name), so the same split always shows
/// the same answer.
List<SplitTransfer> settleTransfers(LoanSplit split) {
  final balances = splitBalances(split);
  final debtors =
      [
        for (final balance in balances)
          if (balance.net < 0) (balance.person, -balance.net),
      ]..sort((a, b) {
        final byAmount = b.$2.compareTo(a.$2);
        return byAmount != 0 ? byAmount : a.$1.compareTo(b.$1);
      });
  final creditors =
      [
        for (final balance in balances)
          if (balance.net > 0) (balance.person, balance.net),
      ]..sort((a, b) {
        final byAmount = b.$2.compareTo(a.$2);
        return byAmount != 0 ? byAmount : a.$1.compareTo(b.$1);
      });

  final transfers = <SplitTransfer>[];
  var debtor = 0, creditor = 0;
  var owes = debtors.isEmpty ? 0 : debtors.first.$2;
  var isOwed = creditors.isEmpty ? 0 : creditors.first.$2;
  while (debtor < debtors.length && creditor < creditors.length) {
    final amount = owes < isOwed ? owes : isOwed;
    if (amount > 0) {
      transfers.add(
        SplitTransfer(
          from: debtors[debtor].$1,
          to: creditors[creditor].$1,
          amount: amount,
        ),
      );
    }
    owes -= amount;
    isOwed -= amount;
    if (owes == 0) {
      debtor++;
      if (debtor < debtors.length) owes = debtors[debtor].$2;
    }
    if (isOwed == 0) {
      creditor++;
      if (creditor < creditors.length) isOwed = creditors[creditor].$2;
    }
  }
  return transfers;
}

/// The split's title as a loan's note, so a transfer recorded as a loan says
/// where it came from without opening the split.
String splitNote(LoanSplit split, String settleWord) {
  final title = split.title.trim();
  return title.isEmpty ? settleWord : '$settleWord: $title';
}

/// Whether [transfer] already has its ordinary loan record.
///
/// The match deliberately leaves the date out: a transfer recorded today and
/// looked at tomorrow is still the same payment, and checking the date would
/// offer to record it a second time. Who, how much and which way make the
/// shape; the link back to the split ([Loan.splitId]) says which payment it
/// is, so renaming the split afterwards cannot make it look unrecorded. A
/// loan recorded before that link was written is matched by its note.
bool splitTransferRecorded(
  Iterable<Loan> loans,
  LoanSplit split,
  SplitTransfer transfer,
  String settleWord,
) {
  final me = personKey(split.me);
  if (me.isEmpty || !transfer.involves(split.me)) return false;
  final other = personKey(transfer.from) == me ? transfer.to : transfer.from;
  final lent = personKey(transfer.to) == me;
  final note = splitNote(split, settleWord);
  return loans.any(
    (loan) =>
        loan.kind == LoanKind.money &&
        loan.currency == 'IRR' &&
        loan.digits == 0 &&
        personKey(loan.person) == personKey(other) &&
        loan.amount == transfer.amount &&
        (loan.direction == LoanDirection.lent) == lent &&
        (loan.splitId.isNotEmpty
            ? loan.splitId == split.id
            // A loan from before the link (2.8.19): its note, and not
            // written before the split's own day — so another split that
            // happens to share a title is not marked as recorded by it.
            : loan.note == note && loan.issued.compareTo(split.date) >= 0),
  );
}

/// A civil date key for a new split, kept out of the widget layer.
String splitToday() => civilDateKey(DateTime.now());
