import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/cheques/values.dart';
import 'package:nex_client/modules/cheques/model.dart';
import 'package:nex_client/modules/cheques/logic.dart';
import 'package:nex_client/modules/cheques/reminders.dart';
import 'package:nex_client/modules/cheques/ai_contract.dart';

import 'fixtures.dart';

void main() {
  test('Rial/Toman precision, bounds, grouping and three numeric scripts', () {
    expect(enteredAmount('۱٬۲۳۴', 'toman'), BigInt.from(12340));
    expect(enteredAmount('١٢٣٤', 'rial'), BigInt.from(1234));
    expect(enteredAmount('0001', 'rial'), BigInt.one);
    expect(enteredAmount('9' * 24, 'rial')!.toString(), '9' * 24);
    expect(enteredAmount('9' * 24, 'toman'), isNull);
    for (final text in [
      '',
      '0',
      '-1',
      '+1',
      '1.2',
      '1,23',
      '1 000',
      '1,',
      '12abc',
      '1e8',
      '9' * 25,
    ]) {
      expect(enteredAmount(text, 'rial'), isNull, reason: text);
    }
    expect(enteredAmount('10', 'usd'), isNull);
    expect(() => amountForEdit(BigInt.one, 'toman'), throwsFormatException);
    expect(amountForEdit(BigInt.from(11), 'rial'), '11');
  });
  test(
    'civil dates are strict, leap-aware and day differences ignore DST lengths',
    () {
      for (final text in [
        '2026-02-30',
        '2025-02-29',
        '2101-01-01',
        '2026-13-01',
        '2026-1-1',
        '۱۴۰۵-۰۸-۲۶',
      ]) {
        expect(chequeDay(text), isNull);
      }
      expect(chequeDayKey(chequeDay('2028-02-29')!), '2028-02-29');
      expect(
        chequeDaysBetween(DateTime(2026, 3, 21, 23), DateTime(2026, 3, 22, 1)),
        1,
      );
    },
  );
  test('settlement replay preserves an exact remainder and requires a valid state chain', () {
    final body = chequeRaw(amount: '999999999999999999999999');
    body['events'] = [chequeEvent(amount: '999999999999999999999998')];
    final c = Cheque('a', body);
    expect(c.valid, isTrue);
    expect(c.remaining, BigInt.one);
    final full = {
      ...body,
      'status': 'settled',
      'events': [
        ...c.events,
        chequeEvent(id: 'last', amount: '1', next: 'settled'),
      ],
    };
    expect(Cheque('a', full).valid, isTrue);
    expect(Cheque('a', {...full, 'amountRial': '100'}).valid, isFalse);
    expect(
      Cheque('a', {
        ...body,
        'events': [chequeEvent(previous: 'bounced')],
      }).valid,
      isFalse,
    );
    expect(
      Cheque('a', {
        ...body,
        'events': [chequeEvent(next: 'cancelled')],
        'status': 'cancelled',
      }).valid,
      isFalse,
    );
    expect(
      Cheque('a', {
        ...body,
        'events': [chequeEvent(amount: '0')],
      }).valid,
      isFalse,
    );
  });
  test('reversed events are preserved but never counted', () {
    final body = chequeRaw();
    body['events'] = [chequeEvent(amount: '900', voided: true)];
    final c = Cheque('a', body);
    expect(c.valid, isTrue);
    expect(c.paid, BigInt.zero);
    expect(c.remaining, BigInt.from(1000));
    expect(c.locked, isFalse);
  });
  test('unsupported schema, malformed history and invalid direction states are excluded', () {
    for (final patch in [
      <String, Object?>{'v': 9},
      {'amountRial': 10.5},
      {
        'events': [3],
      },
      {
        'events': [chequeEvent(), chequeEvent()],
      },
      {'status': 'settled'},
      {
        'status': 'deposited',
        'events': [chequeEvent(kind: 'status', next: 'deposited')],
      },
      {'sayad': '123'},
      {
        'reminderDays': [0, 0],
      },
      {'minutes': 1440},
      {'note': 17},
      {'due': '2026-02-30'},
      {'sayadCheckedDay': 'oops'},
      {'remind': true, 'reminderDays': <int>[]},
    ]) {
      expect(
        Cheque('a', {...chequeRaw(), ...patch}).valid,
        isFalse,
        reason: patch.toString(),
      );
    }
  });
  test('outlook separates incoming, excludes guarantee/transfer and never hides past due inside future totals', () {
    final today = DateTime(2026, 11, 17);
    Cheque c(String id, Map<String, Object?> body) => Cheque(id, body);
    final transferred = {
      ...chequeRaw(direction: 'incoming'),
      'status': 'transferred',
      'events': [chequeEvent(kind: 'status', next: 'transferred')],
    };
    final rows = [
      c('past', chequeRaw(date: '2026-11-16')),
      c('today', chequeRaw(date: '2026-11-17')),
      c('last', chequeRaw(date: '2026-11-23', direction: 'incoming')),
      c('next', chequeRaw(date: '2026-11-24')),
      c('guarantee', chequeRaw(purpose: 'guarantee')),
      c('transfer', transferred),
    ];
    final windows = chequeOutlook(rows, today);
    expect(windows[0].outgoing, BigInt.from(1000));
    expect(windows[0].incoming, BigInt.from(1000));
    expect(windows[1].outgoing, BigInt.from(1000));
    expect(windows.expand((w) => w.items).map((c) => c.id), [
      'today',
      'last',
      'next',
    ]);
    expect(chequeOverdue(rows.first, today), isTrue);
    expect(rows.first.status, 'active');
    expect(actionableCheques(rows).first.id, 'past');
    expect(
      actionableCheques(rows).map((c) => c.id),
      isNot(contains('transfer')),
    );
  });
  test('guarantees may omit a review date, but enabled alarms need one', () {
    final raw = chequeRaw(purpose: 'guarantee', date: '');
    expect(Cheque('a', raw).valid, isTrue);
    expect(Cheque('a', {...raw, 'remind': true}).valid, isFalse);
    expect(
      Cheque('a', {
        ...raw,
        'events': [chequeEvent()],
      }).valid,
      isFalse,
    );
  });
  test(
    'alarm plans have stable local clock slots and skip past/current times',
    () {
      final raw = {...chequeRaw(date: '2026-11-20'), 'remind': true};
      final c = Cheque('a', raw);
      expect(
        chequeAlarmPlan(
          c,
          DateTime(2026, 11, 16),
        ).map((a) => chequeDayKey(a.at)),
        ['2026-11-17', '2026-11-19', '2026-11-20'],
      );
      expect(chequeAlarmPlan(c, DateTime(2026, 11, 19, 9)).map((a) => a.days), [
        0,
      ]);
      expect(chequeAlarmPlan(c, DateTime(2026, 11, 21)), isEmpty);
      expect(
        chequeAlarmPlan(Cheque('a', {...raw, 'remind': false}), DateTime(2026)),
        isEmpty,
      );
      expect(chequeAlarmKey('a', 3), 'cheque:a:3');
    },
  );
  test('AI context is bounded, exact and redacted by default; source IDs remain usable', () {
    final rows = [
      for (var i = 0; i < 30; i++)
        Cheque(
          'c$i',
          chequeRaw(
            amount: '999999999999999999999999',
            sayad: '0012345678901234',
          ),
        ),
    ];
    final context = ChequeContextV1.build(rows, DateTime(2026, 11, 17));
    expect(context['openCount'], 30);
    expect(context['omittedCount'], 18);
    final items = context['items'] as List;
    expect(items.length, 12);
    expect((items.first as Map)['ref'], 'c0');
    final encoded = jsonEncode(context);
    expect(encoded, isNot(contains('Sample party')));
    expect(encoded, isNot(contains('0012345678901234')));
    expect(encoded, isNot(contains('Private note')));
    expect(encoded, isNot(contains('Sample bank')));
    expect(
      ((context['weeks'] as List).first as Map)['outgoingRial'],
      (BigInt.parse('999999999999999999999999') * BigInt.from(30)).toString(),
    );
    expect(
      jsonEncode(
        ChequeContextV1.build(rows, DateTime(2026, 11, 17), includeNames: true),
      ),
      contains('Sample party'),
    );
    expect(
      () => ChequeContextV1.build(rows, DateTime(2026), limit: 21),
      throwsArgumentError,
    );
  });
  test('future AI draft proposals reject unknown operations and ambiguous malformed amounts', () {
    final proposal = ChequeDraftProposalV1.parse({
      'v': 1,
      'fields': {'amountRial': '1000', 'party': 'Test'},
      'uncertain': ['party'],
    });
    expect(proposal.uncertain, {'party'});
    expect(() => proposal.fields['amountRial'] = '0', throwsUnsupportedError);
    for (final fields in [
      {'amountRial': '1e8'},
      {'due': '2026-02-30'},
      {'execute': 'settle'},
      {'sayad': '123'},
      {'direction': 'maybe'},
    ]) {
      expect(
        () => ChequeDraftProposalV1.parse({
          'v': 1,
          'fields': fields,
          'uncertain': [],
        }),
        throwsFormatException,
      );
    }
    expect(
      () => ChequeDraftProposalV1.parse({
        'v': 1,
        'fields': {'party': 'A'},
        'uncertain': ['bank'],
      }),
      throwsFormatException,
    );
  });
}
