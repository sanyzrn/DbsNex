import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/split_math.dart';
import 'package:nex_client/modules/lent_borrowed/split_model.dart';

/// The arithmetic of a shared cost: every rial accounted for, nobody left in
/// the middle, and the same answer every time.
void main() {
  SplitCost cost({
    required int amount,
    required String payer,
    required SplitMode mode,
    required Map<String, int> parts,
  }) => SplitCost(
    id: 'c1',
    title: 'Dinner',
    amount: amount,
    payer: payer,
    mode: mode,
    parts: parts,
  );

  LoanSplit split(List<SplitCost> costs, {List<String>? people}) => LoanSplit(
    id: 's1',
    title: 'Trip',
    date: '2026-11-17',
    me: 'Ali',
    people: people ?? const ['Ali', 'Sara', 'Reza'],
    costs: costs,
  );

  group('dividing one cost', () {
    test('a cost in whole tomans is shared in whole tomans, still adding '
        'up exactly (2.8.4)', () {
      // 100,000 tomans among three: 33,334 + 33,333 + 33,333 tomans, not
      // 33,333.4.
      final parts = splitParts(
        cost(
          amount: 1000000,
          payer: 'Ali',
          mode: SplitMode.equal,
          parts: const {'Reza': 0, 'Ali': 0, 'Sara': 0},
        ),
      );
      expect(parts.values.every((v) => v % 10 == 0), isTrue);
      expect(parts.values.fold(0, (a, b) => a + b), 1000000);
      expect(parts.values.toSet(), {333340, 333330});
      final weighted = splitParts(
        cost(
          amount: 1000000,
          payer: 'Ali',
          mode: SplitMode.shares,
          parts: const {'Ali': 1, 'Sara': 2},
        ),
      );
      expect(weighted.values.every((v) => v % 10 == 0), isTrue);
      expect(weighted.values.fold(0, (a, b) => a + b), 1000000);
      // Rials that are not whole tomans are still shared to the rial.
      final odd = splitParts(
        cost(
          amount: 1000001,
          payer: 'Ali',
          mode: SplitMode.equal,
          parts: const {'Ali': 0, 'Sara': 0},
        ),
      );
      expect(odd.values.fold(0, (a, b) => a + b), 1000001);
    });

    test('equal shares keep every rial, remainder spread by name', () {
      final parts = splitParts(
        cost(
          amount: 100,
          payer: 'Ali',
          mode: SplitMode.equal,
          parts: const {'Reza': 0, 'Ali': 0, 'Sara': 0},
        ),
      );
      expect(parts.values.fold(0, (a, b) => a + b), 100);
      // Ten tomans: four, three and three — the leftover toman to the first
      // name (2.8.4; to the rial it was 34, 33 and 33).
      expect(parts['Ali'], 40);
      expect(parts['Reza'], 30);
      expect(parts['Sara'], 30);
    });

    test('shares weigh the division and keep the remainder', () {
      final parts = splitParts(
        cost(
          amount: 300,
          payer: 'Ali',
          mode: SplitMode.shares,
          parts: const {'Ali': 1, 'Sara': 2},
        ),
      );
      expect(parts, {'Ali': 100, 'Sara': 200});
    });

    test('uneven shares still add up exactly', () {
      final parts = splitParts(
        cost(
          amount: 100,
          payer: 'Ali',
          mode: SplitMode.shares,
          parts: const {'Ali': 1, 'Sara': 1, 'Reza': 1},
        ),
      );
      expect(parts.values.fold(0, (a, b) => a + b), 100);
    });

    test('amounts are used exactly, and a mismatch invents nothing', () {
      expect(
        splitParts(
          cost(
            amount: 100,
            payer: 'Ali',
            mode: SplitMode.amounts,
            parts: const {'Ali': 40, 'Sara': 60},
          ),
        ),
        {'Ali': 40, 'Sara': 60},
      );
      expect(
        splitParts(
          cost(
            amount: 100,
            payer: 'Ali',
            mode: SplitMode.amounts,
            parts: const {'Ali': 40, 'Sara': 50},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('who owes whom', () {
    test('the payer is credited and every share subtracted', () {
      final balances = splitBalances(
        split([
          cost(
            amount: 300,
            payer: 'Sara',
            mode: SplitMode.equal,
            parts: const {'Ali': 0, 'Sara': 0, 'Reza': 0},
          ),
        ]),
      );
      final byName = {for (final b in balances) b.person: b.net};
      expect(byName['Sara'], 200);
      expect(byName['Ali'], -100);
      expect(byName['Reza'], -100);
      expect(balances.fold(0, (a, b) => a + b.net), 0);
    });

    test('everyone is included, even when they come out even', () {
      final balances = splitBalances(
        split(
          [
            cost(
              amount: 100,
              payer: 'Ali',
              mode: SplitMode.equal,
              parts: const {'Ali': 0, 'Sara': 0},
            ),
          ],
          people: ['Ali', 'Sara', 'Reza'],
        ),
      );
      expect(balances.map((b) => b.person), ['Ali', 'Reza', 'Sara']);
      expect(balances.firstWhere((b) => b.person == 'Reza').isEven, isTrue);
    });
  });

  group('settling up', () {
    test('the largest debtor pays the largest creditor first', () {
      final transfers = settleTransfers(
        split([
          cost(
            amount: 300,
            payer: 'Ali',
            mode: SplitMode.equal,
            parts: const {'Ali': 0, 'Sara': 0, 'Reza': 0},
          ),
        ]),
      );
      expect(transfers, hasLength(2));
      expect(transfers.first.from, anyOf('Reza', 'Sara'));
      expect(transfers.first.to, 'Ali');
      expect(transfers.fold(0, (a, t) => a + t.amount), 200);
    });

    test('nobody appears in the middle, and no transfer is zero', () {
      final transfers = settleTransfers(
        split([
          cost(
            amount: 1000,
            payer: 'Ali',
            mode: SplitMode.amounts,
            parts: const {'Ali': 100, 'Sara': 300, 'Reza': 600},
          ),
        ]),
      );
      final paid = <String, int>{};
      final received = <String, int>{};
      for (final transfer in transfers) {
        expect(transfer.amount, greaterThan(0));
        expect(transfer.from, isNot(transfer.to));
        paid[transfer.from] = (paid[transfer.from] ?? 0) + transfer.amount;
        received[transfer.to] = (received[transfer.to] ?? 0) + transfer.amount;
      }
      // Reza pays 500, Sara 200, Ali receives 700: two transfers, not three.
      expect(transfers, hasLength(2));
      expect(received['Ali'], 900);
      expect(paid.values.fold(0, (a, b) => a + b), 900);
    });

    test('a split that is already even asks for nothing', () {
      expect(
        settleTransfers(
          split(
            [
              cost(
                amount: 200,
                payer: 'Ali',
                mode: SplitMode.amounts,
                parts: const {'Ali': 100, 'Sara': 100},
              ),
              cost(
                amount: 100,
                payer: 'Sara',
                mode: SplitMode.amounts,
                parts: const {'Ali': 100, 'Sara': 0},
              ),
            ],
            people: ['Ali', 'Sara'],
          ),
        ),
        isEmpty,
      );
    });

    test('the same split always settles the same way', () {
      final one = settleTransfers(
        split([
          cost(
            amount: 100,
            payer: 'Sara',
            mode: SplitMode.equal,
            parts: const {'Ali': 0, 'Sara': 0, 'Reza': 0},
          ),
        ]),
      );
      final two = settleTransfers(
        split([
          cost(
            amount: 100,
            payer: 'Sara',
            mode: SplitMode.equal,
            parts: const {'Ali': 0, 'Sara': 0, 'Reza': 0},
          ),
        ]),
      );
      expect(
        [for (final t in one) '${t.from}>${t.to}:${t.amount}'],
        [for (final t in two) '${t.from}>${t.to}:${t.amount}'],
      );
    });
  });
}
