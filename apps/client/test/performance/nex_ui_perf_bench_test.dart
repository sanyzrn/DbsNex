@Tags(['budget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart' show NexLinkFace;
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/platform/vault_store.dart';

/// NEX-UI performance benches: the costs this patch removed, measured
/// against the costs it left, with ratio budgets a regression trips.
///
/// Every "before" arm is the 2.8.3 code path verbatim (or a call of the
/// API that still exists, exactly the way the old build called it); every
/// "after" arm is what production pays now. Ratios, not absolute times,
/// are the budget — a ratio holds on any runner the way a millisecond
/// cannot. Tagged `budget`, so the ordinary suite skips it; CI runs
///
///     flutter test --tags budget --run-skipped test/performance/
void main() {
  int bestOf(List<int> values) => values.reduce((a, b) => a < b ? a : b);

  int us(void Function() body, {int n = 25}) {
    // Warm.
    body();
    final times = <int>[];
    for (var i = 0; i < n; i++) {
      final sw = Stopwatch()..start();
      body();
      times.add(sw.elapsedMicroseconds);
    }
    return bestOf(times);
  }

  group('NEX-UI-03 — what a link card asks of its address', () {
    const urls = [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://github.com/flutter/flutter',
      'https://en.wikipedia.org/wiki/Persian_gulf',
      'https://x.com/somebody/status/1234',
      'https://www.aparat.com/v/abcde',
      'https://maps.app.goo.gl/xyz123',
      'https://example.com/downloads/report-2026.pdf',
      'https://t.me/somebody',
    ];
    test('a re-ask is a map lookup, not a re-parse', () {
      // The 2.8.3 card re-parsed on every rebuild; the parse is now the
      // first ask only. Measure both on the working set the cards hold.
      final parsed = us(() {
        for (final url in urls) {
          // Distinct working set, fresh addresses: every ask is a miss.
          NexLinkFace.of('$url?fresh=${DateTime.now().microsecondsSinceEpoch}');
        }
      }, n: 15);
      // Warm the memo for the real working set.
      for (final url in urls) {
        NexLinkFace.of(url);
      }
      final remembered = us(() {
        for (final url in urls) {
          NexLinkFace.of(url);
        }
      }, n: 25);

      // ignore: avoid_print
      print(
        'BENCH link-face per url x${urls.length}: '
        'parsed=${(parsed / urls.length).toStringAsFixed(1)}us '
        'memoHit=${(remembered / urls.length).toStringAsFixed(1)}us '
        'ratio=${(parsed / remembered).toStringAsFixed(0)}x',
      );
      expect(
        parsed > remembered * 4,
        isTrue,
        reason:
            'a remembered face must be several times cheaper than a '
            're-parse of the address',
      );
    });
  });

  group('NEX-UI-04 — what the vault list pays per rebuild', () {
    test('the pass that does not change anything is not re-run', () {
      const count = 500;
      final entries = List.generate(count, (i) {
        return VaultEntry(
          id: 'v$i',
          kind: VaultKind.password,
          fields: {
            'title': 'Account $i of the vault',
            'login': 'user$i@example.test',
            'website': 'site$i.example.org',
            'bank': 'bank $i',
            'holder': 'Holder $i',
          },
          updatedAt: DateTime.utc(2026, 1, 1, 0, i ~/ 60, i % 60),
          favorite: i % 17 == 0,
        );
      });
      const query = 'user4';

      // The 2.8.3 build's filter body, verbatim — the guard's inputs are
      // parameters, the way a build reads them, not constants to fold away.
      // The haystack was built and lower-cased per entry per rebuild: a
      // copy tap's feedback paid for this, a reveal tick paid for this,
      // every keystroke paid for this.
      int fullPass(String? focusId, bool favorites) {
        final kind = VaultKind.password;
        final items =
            entries
                .where(
                  (e) =>
                      e.kind == kind &&
                      (focusId == null || e.id == focusId) &&
                      (!favorites || e.favorite) &&
                      [
                        e.title,
                        e.value('login'),
                        e.value('website'),
                        e.value('bank'),
                        e.value('holder'),
                      ].join(' ').toLowerCase().contains(query),
                )
                .toList()
              ..sort((a, b) {
                final favorite = (b.favorite ? 1 : 0).compareTo(
                  a.favorite ? 1 : 0,
                );
                return favorite != 0
                    ? favorite
                    : b.updatedAt.compareTo(a.updatedAt);
              });
        return items.length;
      }

      // What a rebuild that changes nothing pays now: the key comparison
      // — the same guard production runs against the memo — and the
      // remembered list handed straight back.
      // The memo the screen now keeps: the key comparison, the remembered
      // list handed straight back when nothing it names has moved.
      List<VaultEntry> cacheSource = entries;
      String cacheQuery = query;
      bool cacheFavorites = false;
      VaultKind cacheKind = VaultKind.password;
      String? cacheFocus;
      List<VaultEntry>? memoHit(String? focusId, bool favorites) {
        if (identical(cacheSource, entries) &&
            cacheQuery == query &&
            cacheFavorites == favorites &&
            cacheKind == VaultKind.password &&
            cacheFocus == focusId) {
          return entries;
        }
        return null;
      }

      expect(fullPass(null, false), greaterThan(0));
      expect(memoHit(null, false), isNotNull);

      final cold = us(() => fullPass(null, false), n: 5);
      final warm = us(() => memoHit(null, false), n: 25);
      final ratio = warm > 0 ? '${(cold / warm).toStringAsFixed(0)}x' : '∞';
      // ignore: avoid_print
      print(
        'BENCH vault-filter @$count entries: '
        'fullPass=${cold.toStringAsFixed(1)}us/rebuild '
        'memoHit=${warm.toStringAsFixed(2)}us/rebuild '
        'ratio=$ratio '
        '(the full pass runs once per real change; every other rebuild '
        'was paying it before)',
      );
      expect(
        cold > warm * 50,
        isTrue,
        reason: 'a rebuild that changes nothing must not re-run the pass',
      );
    });
  });

  group('NEX-UI-05 — what the loans list pays per build', () {
    test('one bucketed pass beats scanning twice per loan', () {
      const loans = 100;
      const returns = 300;
      final all = List.generate(loans, (i) {
        return Loan(
          id: 'loan-$i',
          direction: LoanDirection.lent,
          person: 'Person $i',
          kind: LoanKind.money,
          amount: 100000 + i,
          what: '',
          issued: '2026-10-01',
          due: i % 5 == 0 ? null : '2026-11-0${(i % 9) + 1}',
          note: '',
        );
      });
      final history = List.generate(returns, (i) {
        return LoanReturn(
          id: 'ret-$i',
          loanId: 'loan-${i % loans}',
          date: '2026-10-15',
          amount: 100,
        );
      });

      // The 2.8.3 shape: the filter pass asked standing() per loan, the
      // standings map asked again — two whole-list scans per loan per
      // build.
      int doubleScan() {
        var open = 0;
        for (final loan in all) {
          final pass1 = LoanMath.standing(loan, history);
          final pass2 = LoanMath.standing(loan, history);
          if (pass1.outstanding > 0 && pass2.outstanding > 0) open++;
        }
        return open;
      }

      int onePass() => LoanMath.standingsOf(all, history).length;

      expect(doubleScan() > 0, isTrue);
      expect(onePass(), loans);

      final before = us(() => doubleScan(), n: 5);
      final after = us(() => onePass(), n: 5);
      // ignore: avoid_print
      print(
        'BENCH loans-standings ${loans}x$returns: '
        'twoScansPerLoan=${before.toStringAsFixed(0)}us '
        'standingsOf=${after.toStringAsFixed(0)}us '
        'ratio=${(before / after).toStringAsFixed(0)}x',
      );
      expect(
        before > after * 2,
        isTrue,
        reason:
            'the whole list must be answered in less than half of the '
            'twice-per-loan scans',
      );
    });
  });
}
