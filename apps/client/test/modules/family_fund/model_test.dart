import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/family_fund/model.dart';
import 'package:nex_client/modules/family_fund/projection.dart';

Fund example(NexModuleMonth month) => Fund('x', {
  'v': 1,
  'name': 'Family',
  'rules': '',
  'shareRial': 5000,
  'paymentDay': 31,
  'drawDay': 30,
  'start': dayKey(month.first),
  'members': [
    for (final (i, n) in ['Ali', 'Mina', 'Sara'].indexed)
      <String, Object?>{
        'id': '$i',
        'person': {'name': n},
        'shares': i + 1,
        'from': dayKey(month.first),
      },
  ],
  'payments': <Fields>[],
  'draws': <Fields>[],
  'loans': <Fields>[],
});

ModuleRecord record(Fields body) => ModuleRecord(
  module: 'family_fund',
  kind: 'fund',
  id: 'x',
  body: body,
  updatedAt: DateTime(2025),
);

void main() {
  const esfand = NexModuleMonth(true, 1403, 12);
  test('Esfand clamps correctly in leap and regular years, then rolls to Farvardin', () {
    expect(nexPersianDate(dueDay(esfand, 31)).day, 30);
    expect(
      nexPersianDate(dueDay(const NexModuleMonth(true, 1404, 12), 31)).day,
      29,
    );
    expect(esfand.shift(1), const NexModuleMonth(true, 1404, 1));
    final dues = FundDues(example(esfand))
        .duesBetween(dueDay(esfand, 30), dueDay(esfand, 30));
    expect(dues.map((d) => d.amountRial), [5000, 10000, 15000, null]);
    expect(dues.every((d) => d.private && !d.done), isTrue);
  });

  test('redraw requires a reason, retains the old pool and excludes previous picks', () {
    var f = example(esfand);
    final day = dueDay(esfand, 30);
    f = Fund(f.id, f.draw(esfand, day, 'd1', '', Random(0)));
    expect(() => f.draw(esfand, day, 'bad', ' ', Random(0)), throwsStateError);
    final first = f.winner(esfand)!['winner'];
    f = Fund(f.id, f.draw(esfand, day, 'd2', 'Documented reason', Random(0)));
    expect(f.draws, hasLength(2));
    expect(rows(f.draws.first['eligible']), hasLength(3));
    expect(rows(f.draws.last['eligible']), hasLength(2));
    expect(f.winner(esfand)!['winner'], isNot(first));
    final pool = f.drawPool(esfand.shift(1));
    expect(
      pool.eligible.map((m) => m['id']),
      isNot(contains(f.winner(esfand)!['winner'])),
    );
    expect(pool.eligible.map((m) => m['id']), contains(first));
  });

  test(
    'three effective winners exhaust the round and the next month restarts it',
    () {
      var f = example(esfand);
      for (var i = 0; i < 3; i++) {
        final month = esfand.shift(i);
        expect(f.drawPool(month).eligible, hasLength(3 - i));
        f = Fund(f.id, f.draw(month, month.first, '$i', '', Random(i)));
      }
      expect(f.drawPool(esfand.shift(3)).round, 2);
      expect(f.drawPool(esfand.shift(3)).eligible, hasLength(3));
      expect(f.drawPool(esfand).eligible, isEmpty);
    },
  );

  test(
    'departure preserves eligibility for historical contribution months',
    () {
      final f = example(esfand);
      final departed = {
        ...f.members.first,
        'until': dayKey(esfand.shift(1).first),
      };
      final updated = Fund(f.id, {
        ...f.body,
        'members': [departed, ...f.members.skip(1)],
      });
      expect(updated.active(esfand), hasLength(3));
      expect(updated.active(esfand.shift(1)), hasLength(2));
    },
  );

  test('instalments sum exactly, cash only counts recorded events, payout locks redraw', () {
    final f = example(esfand);
    final d = Fund(f.id, f.draw(esfand, esfand.first, 'd1', '', Random(1)));
    final parts = instalments(1001, 3, esfand.shift(1), 31);
    expect(parts.map((p) => p['amountRial']), [333, 333, 335]);
    final loan = <String, Object?>{
      'draw': 'd1',
      'at': dayKey(esfand.first),
      'amountRial': 1001,
      'person': {'name': 'Mina'},
      'instalments': [
        {...parts.first, 'paidAt': dayKey(esfand.shift(1).first)},
        ...parts.skip(1),
      ],
    };
    final logged = Fund.read(
      record({
        ...d.body,
        'payments': [
          <String, Object?>{
            'member': '0',
            'month': dayKey(esfand.first),
            'at': dayKey(esfand.first),
            'amountRial': 5000,
          },
        ],
        'loans': [loan],
      }),
    )!;
    expect(logged.balanceAt(esfand.first), 3999);
    expect(logged.balanceAt(esfand.shift(1).first), 4332);
    expect(logged.drawPool(esfand).eligible, isEmpty);
  });

  test('invalid and future versions do not produce private summaries', () {
    final f = example(esfand);
    expect(summarize(record(f.body))!.private, isTrue);
    expect(summarize(record({...f.body, 'v': 2})), isNull);
    expect(summarize(record({...f.body, 'paymentDay': null})), isNull);
    expect(summarize(record({...f.body, 'start': '2025-02-30'})), isNull);
  });
}
