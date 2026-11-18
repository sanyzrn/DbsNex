import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/modules/cheques/dues.dart';
import 'package:nex_client/modules/cheques/model.dart';
import 'package:nex_client/modules/cheques/logic.dart';
import 'package:nex_client/modules/cheques/repository.dart';
import 'package:nex_client/modules/cheques/plan_model.dart';
import 'package:nex_client/modules/cheques/plan_repository.dart';
import 'package:nex_client/modules/cheques/reminders.dart';
import 'package:nex_client/modules/cheques/summary.dart';
import 'package:nex_client/modules/cheques/values.dart';
import 'package:nex_client/modules/cheques/money_format.dart';
import 'package:nex_client/modules/cheques/irr_unit.dart';
import 'package:nex_client/modules/cheques/privacy.dart';
import 'package:nex_client/modules/cheques/share.dart';

import '../../support/nex_harness.dart';
import 'fixtures.dart';
import 'plan_test.dart' show planRaw;

ModuleRecord record(String kind, String id, Map<String, Object?> body) =>
    ModuleRecord(
      module: 'cheques',
      kind: kind,
      id: id,
      body: body,
      updatedAt: DateTime(2026),
    );

void main() {
  test(
    'inclusive civil ranges span leap and non-leap Esfand without overflow',
    () {
      for (final year in [1403, 1404]) {
        final last = nexPersianMonthDays(year, 12),
            start = nexGregorianDate(year, 12, 1),
            end = nexGregorianDate(year, 12, last);
        final rows = [
          for (final day in [28, 29, if (last == 30) 30])
            Cheque(
              '$day',
              chequeRaw(date: chequeDayKey(nexGregorianDate(year, 12, day))),
            ),
          Cheque(
            'next',
            chequeRaw(date: chequeDayKey(nexGregorianDate(year + 1, 1, 1))),
          ),
        ];
        final dues = ChequeDues(rows)
            .duesBetween(start, DateTime(end.year, end.month, end.day, 23));
        expect(dues, hasLength(last == 30 ? 3 : 2));
        expect(dues.last.at, end);
        expect(dues.every((d) => !d.at.isUtc && d.at.hour == 0), isTrue);
        expect(ChequeDues(rows).duesBetween(end, start), isEmpty);
      }
    },
  );

  test('one snapshot provides signs, remainders, guarantees, done flags and routes', () {
    final out = Cheque('out', {
          ...chequeRaw(),
          'events': [chequeEvent(amount: '300')],
        }),
        incoming = Cheque('in', chequeRaw(direction: 'incoming')),
        guarantee = Cheque('review', chequeRaw(purpose: 'guarantee')),
        paid = Cheque('paid', {
          ...chequeRaw(),
          'status': 'settled',
          'events': [chequeEvent(amount: '1000', next: 'settled')],
        }),
        plan = InstalmentPlan('p', {
          ...planRaw(),
          'first': '2026-11-20',
          'paid': {'0': '2026-11-17'},
        });
    final rows = [out, incoming, guarantee, paid, ...plan.cheques()];
    final dues = ChequeDues(rows)
        .duesBetween(DateTime(2026, 11, 20), DateTime(2026, 11, 20));
    expect(dues.firstWhere((d) => d.recordId == 'out').amountRial, -700);
    expect(dues.firstWhere((d) => d.recordId == 'in').amountRial, 1000);
    expect(dues.firstWhere((d) => d.recordId == 'review').amountRial, isNull);
    expect(dues.firstWhere((d) => d.recordId == 'paid').done, isTrue);
    final instalment = dues.singleWhere((d) => d.recordKind == 'plan');
    expect(instalment.id, 'plan:p:0');
    expect(instalment.recordId, 'p');
    expect(instalment.done, isTrue);
    expect(dues.every((d) => d.private), isTrue);
    final window = ChequeWindow(
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 21),
      rows,
    );
    expect(window.incoming, BigInt.from(1000));
    expect(window.outgoing, BigInt.from(700));
    final projection = ChequeDues.fromRecords([
      record('cheque', 'in', incoming.raw),
      record('plan', 'p', plan.raw),
    ]);
    expect(
      projection
          .duesBetween(DateTime(2026, 11, 20), DateTime(2026, 11, 20))
          .map((d) => d.id),
      ['cheque:in', 'plan:p:0'],
    );
  });

  test('missing, malformed and future data produce no dates or summaries', () {
    for (final raw in [
      <String, Object?>{},
      {...chequeRaw()}..remove('due'),
      {...chequeRaw(), 'v': 99},
      {...chequeRaw(), 'due': '2026-02-30'},
    ]) {
      expect(
        ChequeDues([Cheque('bad', raw)])
            .duesBetween(DateTime(1900), DateTime(2100)),
        isEmpty,
      );
      expect(summarize(record('cheque', 'bad', raw)), isNull);
    }
    expect(
      ChequeDues.fromRecords([
        record('draft', 'x', chequeRaw()),
        record('plan', 'p', {}),
      ]).rows,
      isEmpty,
    );
    expect(summarize(record('draft', 'x', chequeRaw())), isNull);
    expect(summarize(record('plan', 'p', planRaw()))!.private, isTrue);
    expect(
      summarize(record('cheque', 'x', chequeRaw()))!.title,
      'Sample party',
    );
  });

  test(
    'legacy 24-digit values stay exact and never become a saturated shared int',
    () {
      final c = Cheque('legacy', chequeRaw(amount: '999999999999999999999999'));
      final due = ChequeDues([c]).duesBetween(c.due!, c.due!).single;
      expect(c.valid, isTrue);
      expect(due.amountRial, isNull);
      expect(c.face.toString(), '999999999999999999999999');
      expect(storedRials('9007199254740993'), '9007199254740993');
      expect(editableAmount(c.face.toString(), 'rial'), isNull);
      expect(
        editableAmount(c.face.toString(), 'rial', original: c.face),
        c.face,
      );
      expect(parseAmount('۱۲٬۳۴۵٫۶', 'IRR', 0, IrrUnit.toman), 123456);
      expect(enteredAmount('۱۲٬۳۴۵٫۶', 'toman'), BigInt.from(123456));
      expect(
        formatAmount(123456, 'IRR', 0, true, IrrUnit.toman),
        '۱۲٬۳۴۵٫۶ تومان',
      );
    },
  );

  test(
    'calendar and reminder share the date for all six standard lead times',
    () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('fa'));
      for (final offsets in [
        [0, 1, 3],
        [7, 14, 30],
      ]) {
        final c = Cheque('a', {
          ...chequeRaw(date: '2027-03-20'),
          'remind': true,
          'reminderDays': offsets,
        });
        final due = ChequeDues([c]).duesBetween(c.due!, c.due!).single;
        final alarms = chequeAlarmPlan(c, DateTime(2027, 1));
        expect(alarms, hasLength(3));
        for (final alarm in alarms) {
          expect(chequeDaysBetween(alarm.at, due.at), alarm.days);
          final text = chequeAlarmText(c, l10n, days: alarm.days);
          expect(text, contains(c.party));
          expect(text, contains(alarm.days == 0 ? 'امروز' : 'روز مانده'));
          expect(text, isNot(contains('روز قبل')));
          expect(text, contains('۱٬۰۰۰'));
          expect(
            text,
            contains(nexReadableDate(due.at, solar: true, persian: true)),
          );
        }
      }
    },
  );

  test('English alarm says how much time remains until the due date', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final c = Cheque('a', chequeRaw());
    expect(chequeAlarmText(c, l10n, days: 3), contains('3 days left'));
    expect(chequeAlarmText(c, l10n), contains('Today'));
  });

  test('saving legacy money/person adds integer rials and keeps future nested fields', () async {
    final h = await NexTestHarness.create(name: 'cheque_shared_');
    addTearDown(h.dispose);
    final store = NexModuleStore(h.services, 'cheques'),
        repo = ChequeRepository(store);
    final legacy = {
      ...chequeRaw(),
      'future': {'v': 9},
      'person': {
        'name': 'Ali',
        'id': 'person-7',
        'cards': ['kept'],
        'ibans': ['kept'],
      },
    };
    await store.put('cheque', 'old', legacy);
    final saved = await repo.save('old', legacy, {'party': 'Reza'});
    expect(saved.raw['amountRial'], 1000);
    expect(saved.party, 'Reza');
    expect(saved.raw['person'], {...legacy['person'] as Map, 'name': 'Reza'});
    expect(saved.raw['future'], legacy['future']);
    final next = await repo.addEvent(
      saved,
      id: 'event',
      kind: 'payment',
      day: DateTime(2026, 11, 17),
      amount: '100',
    );
    expect(next.events.single['amountRial'], 100);
    expect(next.raw['person'], saved.raw['person']);
    final plan = await PlanRepository(store).save('p', null, planRaw());
    expect(plan.raw['totalRial'], 1001);
    // Reviewed and available since 2.8.4.
    expect(nexModulesById['cheques']!.available, isTrue);
  });

  test(
    'new money and lead times use bounds while legacy values survive',
    () async {
      final h = await NexTestHarness.create(name: 'cheque_bounds_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'cheques'),
          repo = ChequeRepository(store),
          plans = PlanRepository(store);
      await expectLater(
        repo.save(
          'oversize',
          null,
          chequeRaw(amount: '999999999999999999999999'),
        ),
        throwsA(isA<ChequeFailure>()),
      );
      await expectLater(
        repo.save('lead', null, {
          ...chequeRaw(),
          'reminderDays': [2],
        }),
        throwsA(isA<ChequeFailure>()),
      );
      await expectLater(
        plans.save('p', null, {...planRaw(), 'beforeDays': 2}),
        throwsA(isA<ChequeFailure>()),
      );
      final legacy = chequeRaw(amount: '999999999999999999999999');
      await store.put('cheque', 'old', legacy);
      final saved = await repo.save('old', legacy, {
        ...legacy,
        'note': 'Changed',
      });
      expect(saved.face.toString(), legacy['amountRial']);
      expect(saved.raw['amountRial'], legacy['amountRial']);
      final settled = await repo.addEvent(
        saved,
        id: 'pay',
        kind: 'payment',
        day: DateTime(2026, 11, 17),
        amount: saved.face.toString(),
      );
      expect(settled.remaining, BigInt.zero);
      expect(settled.closed, isTrue);
      final legacyPlan = {...planRaw(), 'beforeDays': 2};
      await store.put('plan', 'old-plan', legacyPlan);
      expect(
        (await plans.save('old-plan', legacyPlan, {
          ...legacyPlan,
          'title': 'Changed',
        })).raw['beforeDays'],
        2,
      );
    },
  );

  testWidgets(
    'shared text respects hiding and omits bank and personal identifiers',
    (t) async {
      final h = await NexTestHarness.create(name: 'cheque_share_');
      addTearDown(h.dispose);
      String visible = '', hidden = '';
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChequePrivacy(
            child: Builder(
              builder: (context) {
                visible = chequeShareText(context, Cheque('a', chequeRaw()));
                return TextButton(
                  onPressed: () => ChequeVisibility.of(context)!.value = true,
                  child: const Text('Hide'),
                );
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(visible, contains('1,000'));
      expect(visible, isNot(contains('Sample bank')));
      expect(visible, isNot(contains('Private note')));
      await t.tap(find.text('Hide'));
      await t.pump();
      final context = t.element(find.text('Hide'));
      hidden = chequeShareText(context, Cheque('a', chequeRaw()));
      expect(hidden, contains('••••'));
      expect(hidden, isNot(contains('1,000')));
    },
  );
}
