import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/plan_model.dart';
import 'package:nex_client/modules/cheques/plan_repository.dart';
import 'package:nex_client/modules/cheques/plans_page.dart';
import 'package:nex_client/modules/cheques/privacy.dart';
import 'package:nex_client/modules/cheques/home.dart';
import 'package:nex_client/modules/cheques/values.dart';

import '../../support/nex_harness.dart';
import 'widget_test.dart' show settleCheque, reachCheque;

Map<String, Object?> planRaw() => {
  'v': 1,
  'title': 'Laptop',
  'totalRial': '1001',
  'count': 4,
  'months': 1,
  'first': '2026-01-31',
  'calendar': 'gregorian',
  'paid': <String, Object?>{},
  'remind': false,
  'beforeDays': 3,
  'minutes': 540,
};
void main() {
  test(
    'exact instalment division, anchored month-end, and no amount duplication',
    () {
      final p = InstalmentPlan('p', planRaw());
      expect(p.valid, isTrue);
      expect(
        [for (var i = 0; i < 4; i++) p.amount(i).toString()],
        ['250', '250', '250', '251'],
      );
      expect(
        [for (var i = 0; i < 4; i++) chequeDayKey(p.date(i))],
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
      );
      expect(p.cheques().every((c) => c.valid), isTrue);
    },
  );
  test('a total in whole tomans is paid in whole tomans (2.8.4)', () {
    final p = InstalmentPlan('p', {
      ...planRaw(),
      'totalRial': '100000000',
      'count': 3,
    });
    final parts = [for (var i = 0; i < 3; i++) p.amount(i)];
    expect(parts.every((v) => v % BigInt.from(10) == BigInt.zero), isTrue);
    expect(parts.fold(BigInt.zero, (a, b) => a + b), BigInt.from(100000000));
    expect(parts.map((v) => v.toString()), [
      '33333330',
      '33333330',
      '33333340',
    ]);
  });
  test(
    'Jalali monthly anchoring spans leap Esfand with recovery of original day',
    () {
      final first = nexGregorianDate(1403, 11, 30);
      final p = InstalmentPlan('p', {
        ...planRaw(),
        'first': chequeDayKey(first),
        'calendar': 'jalali',
        'count': 15,
      });
      for (var i = 0; i < p.count; i++) {
        final d = nexPersianDate(p.date(i));
        expect(d.day, 30.clamp(1, nexPersianMonthDays(d.year, d.month)));
      }
    },
  );
  test('malformed plans cannot generate financial rows', () {
    for (final patch in <Map<String, Object?>>[
      {'count': 0},
      {'count': 121},
      {'months': 0},
      {'totalRial': '1'},
      {'first': 'bad'},
      {
        'paid': {'9': '2026-01-01'},
      },
      {'beforeDays': 31},
    ]) {
      final p = InstalmentPlan('p', {...planRaw(), ...patch});
      expect(p.valid, isFalse);
      expect(p.cheques(), isEmpty);
    }
  });
  test('paid changes are atomic, stale changes refused, delete and restore preserve history', () async {
    final h = await NexTestHarness.create(name: 'plan_repo_');
    addTearDown(h.dispose);
    final store = NexModuleStore(h.services, 'cheques'),
        repo = PlanRepository(store);
    var p = await repo.save('p', null, planRaw());
    final old = p;
    p = await repo.toggle(p, 0);
    expect(p.paid(0), isTrue);
    expect(p.cheques().first.closed, isTrue);
    await expectLater(repo.toggle(old, 1), throwsException);
    final raw = await repo.delete(p);
    await repo.restore('p', raw);
    expect(await store.get('plan', 'p'), p.raw);
  });
  testWidgets(
    'plan list toggles a payment and amounts hide without changing data',
    (t) async {
      final h = await NexTestHarness.create(name: 'plan_ui_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'cheques'),
          repo = PlanRepository(store);
      await t.runAsync(() => repo.save('p', null, planRaw()));
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChequePrivacy(child: PlansPage(store: store)),
        ),
      );
      await settleCheque(t);
      expect(find.text('Total (Rial): 1,001 Rial'), findsOneWidget);
      await t.tap(find.byTooltip('Hide amounts'));
      await t.pumpAndSettle();
      expect(find.textContaining('••••'), findsWidgets);
      final checkbox = find.byType(CheckboxListTile).first;
      await reachCheque(t, checkbox);
      await t.tap(checkbox);
      await settleCheque(t);
      expect(
        InstalmentPlan('p', (await store.get('plan', 'p'))!).paid(0),
        isTrue,
      );
    },
  );
  testWidgets('monthly cash calendar is reachable and amounts can be hidden', (
    t,
  ) async {
    final h = await NexTestHarness.create(name: 'month_ui_');
    addTearDown(h.dispose);
    final store = NexModuleStore(h.services, 'cheques');
    await t.runAsync(
      () => PlanRepository(
        store,
      ).save('p', null, {...planRaw(), 'first': chequeDayKey(DateTime.now())}),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChequePrivacy(child: ChequeHome(store: store)),
      ),
    );
    await settleCheque(t);
    await t.tap(find.text('Jalali month'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Planned receipts minus payments'),
      findsOneWidget,
    );
    await t.tap(find.byTooltip('Hide amounts'));
    await t.pumpAndSettle();
    expect(find.textContaining('••••'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
