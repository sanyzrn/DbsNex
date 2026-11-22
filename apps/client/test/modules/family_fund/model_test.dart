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

  test('a share change applies from its month and never rewrites the past', () {
    final f = example(esfand);
    final later = esfand.shift(2);
    final body = f.withShare(later, 9000);
    final changed = Fund('x', body);
    expect(changed.shareFor(esfand), 5000);
    expect(changed.shareFor(esfand.shift(1)), 5000);
    expect(changed.shareFor(later), 9000);
    expect(changed.potFor(later), 9000 * 6);
    expect(changed.collectedFor(later), 0);
    expect(rows(body['shareChanges']), hasLength(1));
    final back = changed.withShare(later, 5000);
    expect(rows(back['shareChanges']), isEmpty);
    expect(Fund('x', back).shareFor(later), 5000);
    final second = Fund('x', changed.withShare(esfand.shift(4), 12000));
    expect(second.shareFor(later), 9000);
    expect(second.shareFor(esfand.shift(4)), 12000);
    expect(second.shareFor(esfand.shift(5)), 12000);
  });

  test('share changes keep unknown fields and are validated on read', () {
    final f = example(esfand);
    final later = esfand.shift(2);
    final changed = {
      ...f.withShare(later, 9000),
      'futureField': {'kept': true},
    };
    expect(changed['futureField'], {'kept': true});
    final read = Fund.read(record(changed));
    expect(read, isNotNull);
    expect(read!.shareChanges.single['shareRial'], 9000);
    expect(
      Fund.read(
        record({
          ...changed,
          'shareChanges': [
            {'from': dayKey(esfand.dayAt(15)), 'shareRial': 9000},
          ],
        }),
      ),
      isNull,
    );
    expect(
      Fund.read(
        record({
          ...changed,
          'shareChanges': [
            {'from': dayKey(esfand.first), 'shareRial': 0},
          ],
        }),
      ),
      isNull,
    );
  });

  test('a redundant share entry keeps fields a later version added', () {
    final f = Fund('x', {
      ...example(esfand).body,
      'shareChanges': [
        <String, Object?>{
          'from': dayKey(esfand.first),
          'shareRial': 5000,
          'note': 'kept',
        },
      ],
    });
    final changes = rows(f.withShare(esfand, 5000)['shareChanges']);
    expect(changes, hasLength(1));
    expect(changes.single['note'], 'kept');
    expect(changes.single['shareRial'], 5000);
  });

  test('a fund with no members has neither a contribution nor a draw due', () {
    final f = Fund('x', {...example(esfand).body, 'members': <Fields>[]});
    expect(FundDues(f).forMonth(esfand), isEmpty);
  });

  test('dues use the share in force for that month', () {
    final f = Fund('x', example(esfand).withShare(esfand, 7000));
    final dues = FundDues(f).forMonth(esfand);
    expect(
      dues.where((d) => d.kind == 'fund-contribution').map((d) => d.amountRial),
      [7000, 14000, 21000],
    );
    expect(f.potFor(esfand), 42000);
  });

  test('a round knows who has received the fund and who is still waiting', () {
    var f = example(esfand);
    f = Fund(f.id, f.draw(esfand, esfand.first, 'd1', '', Random(0)));
    f = Fund(
      f.id,
      f.draw(esfand.shift(1), esfand.shift(1).first, 'd2', '', Random(1)),
    );
    final round = f.roundFor(esfand.shift(2));
    expect(round.number, 1);
    expect(round.received, 2);
    expect(round.total, 3);
    expect(round.remaining, hasLength(1));
    expect(round.complete, isFalse);
    final last = f.draw(
      esfand.shift(2),
      esfand.shift(2).first,
      'd3',
      '',
      Random(2),
    );
    final full = Fund(f.id, last).roundFor(esfand.shift(2));
    expect(full.received, 3);
    expect(full.remaining, isEmpty);
    expect(full.complete, isTrue);
    expect(Fund(f.id, last).roundFor(esfand.shift(3)).number, 2);
  });

  test('a draw snapshot keeps every eligible member and their shares', () {
    final f = Fund(
      'x',
      example(esfand).draw(esfand, esfand.first, 'd1', '', Random(0)),
    );
    final pool = rows(f.draws.single['eligible']);
    expect(pool, hasLength(3));
    expect(pool.every((member) => member['shares'] is int), isTrue);
    expect(pool.every((member) => member['person'] is Map), isTrue);
  });

  test(
    'unpaid months are counted only once their contribution day has gone',
    () {
      final f = example(esfand);
      final due = esfand.dayAt(30);
      expect(f.arrearsFor(f.members.first, due), isEmpty);
      final after = due.add(const Duration(days: 1));
      expect(f.arrearsFor(f.members.first, after).map((a) => a.amountRial), [
        5000,
      ]);
      expect(f.arrearsFor(f.members.last, after).map((a) => a.amountRial), [
        15000,
      ]);
      final paid = Fund(f.id, {
        ...f.body,
        'payments': [
          <String, Object?>{
            'member': '0',
            'month': dayKey(esfand.first),
            'at': dayKey(esfand.first),
            'amountRial': 5000,
          },
        ],
      });
      expect(paid.arrearsFor(paid.members.first, after), isEmpty);
      expect(paid.arrearsFor(paid.members[1], after), hasLength(1));
    },
  );

  test('a payout day may not be left with less than no cash', () {
    final base = example(esfand);
    final drawn = Fund(
      'x',
      base.draw(esfand, esfand.first, 'd1', '', Random(1)),
    );
    final payment = <String, Object?>{
      'member': '0',
      'month': dayKey(esfand.first),
      'at': dayKey(esfand.first),
      'amountRial': 5000,
    };
    final loan = <String, Object?>{
      'draw': 'd1',
      'at': dayKey(esfand.first),
      'amountRial': 1001,
      'person': {'name': 'Ali'},
      'instalments': instalments(1001, 1, esfand.shift(1), 31),
    };
    final sound = Fund('x', {
      ...drawn.body,
      'payments': [payment],
      'loans': [loan],
    });
    expect(sound.keepsLedgerSound(sound.body), isTrue);
    expect(
      sound.keepsLedgerSound({
        ...drawn.body,
        'payments': <Fields>[],
        'loans': [loan],
      }),
      isFalse,
    );
  });

  test('a stored month must be the first day of its own month', () {
    final f = example(esfand);
    final middle = dayKey(esfand.dayAt(15));
    expect(
      Fund.read(
        record({
          ...f.body,
          'payments': [
            <String, Object?>{
              'member': '0',
              'month': middle,
              'at': dayKey(esfand.first),
              'amountRial': 5000,
            },
          ],
        }),
      ),
      isNull,
    );
    expect(
      Fund.read(
        record({
          ...f.body,
          'members': [
            for (final member in f.members)
              member['id'] == '0' ? {...member, 'from': middle} : member,
          ],
        }),
      ),
      isNull,
    );
  });
}
