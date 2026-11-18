import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/modules/module_shared.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/widgets/tool_dates.dart';

import 'support/nex_harness.dart';

/// 2.8.4: the modules' dates gathered on the home screen.
void main() {
  final l10n = AppLocalizationsEn();
  final now = DateTime(2026, 11, 18, 10);
  ModuleDue due(
    String id,
    DateTime at, {
    bool private = false,
    bool done = false,
  }) => ModuleDue(
    id: id,
    recordKind: 'r',
    recordId: id,
    at: at,
    title: 'Title $id',
    kind: 'k',
    private: private,
    done: done,
  );

  test('done and far-off items are left out; private ones share one line '
      'under the module name, never their own title', () {
    final cheques = nexModulesById['cheques']!;
    final parking = nexModulesById['parking']!;
    final lines = nexToolDates(
      {
        cheques: [
          due('a', DateTime(2026, 11, 20), private: true),
          due('b', DateTime(2026, 11, 15), private: true),
          due('c', DateTime(2026, 11, 19), private: true, done: true),
        ],
        parking: [
          due('p', DateTime(2026, 11, 18, 17)),
          due('far', DateTime(2026, 12, 30)),
        ],
      },
      l10n,
      now,
    );
    expect(lines.map((l) => l.title), ['Cheques & instalments', 'Title p']);
    expect(lines.first.count, 2);
    expect(lines.first.at, DateTime(2026, 11, 15));
  });

  test(
    'a birthday that has gone by is not late; a cheque still is (2.8.6)',
    () {
      final occasions = nexModulesById['occasions']!;
      final cheques = nexModulesById['cheques']!;
      ModuleDue day(String id, DateTime at) => ModuleDue(
        id: id,
        recordKind: 'occasion',
        recordId: id,
        at: at,
        title: 'Sara',
        kind: 'birthday',
        passes: true,
      );
      final lines = nexToolDates(
        {
          occasions: [
            day('gone', DateTime(2026, 11, 1)),
            day('today', DateTime(2026, 11, 18)),
          ],
          cheques: [due('late', DateTime(2026, 11, 10), private: true)],
        },
        l10n,
        now,
      );
      expect(lines.map((l) => l.id), ['private:cheques', 'occasions:today']);
      // One private item still says it is one, under the module's name.
      expect(lines.first.grouped, isTrue);
      expect(lines.first.count, 1);
    },
  );

  testWidgets('the card shows the nearest two and folds open to the rest', (
    tester,
  ) async {
    final h = await NexTestHarness.create(name: 'tool_dates_fold_');
    addTearDown(h.dispose);
    await h.preferences.setModuleOn('maintenance', true);
    final soon = DateTime.now().add(const Duration(days: 3));
    final day = DateTime(soon.year, soon.month, soon.day).toIso8601String();
    await tester.runAsync(() async {
      final store = NexModuleStore(h.services, 'maintenance');
      for (final name in ['Pride', 'Peugeot']) {
        await store.put('asset', name, {
          'nickname': name,
          'type': 'car',
          'meterKind': 'none',
          'insuranceExpiresAt': day,
          'inspectionExpiresAt': day,
          'schema': 2,
        });
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexToolDates(services: h.services, preferences: h.preferences),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('in 3 days'), findsNWidgets(2));
    expect(find.text('+2 more'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tool-dates-fold')));
    await tester.pumpAndSettle();
    expect(find.text('in 3 days'), findsNWidgets(4));
    expect(h.preferences.toolDatesOpen, isTrue);
    await tester.tap(find.byKey(const ValueKey('tool-dates-fold')));
    await tester.pumpAndSettle();
    expect(find.text('in 3 days'), findsNWidgets(2));
  });

  testWidgets('a car whose insurance ends this week is on the home card, '
      'and the switch in Home layout takes it away', (tester) async {
    final h = await NexTestHarness.create(name: 'tool_dates_');
    addTearDown(h.dispose);
    await h.preferences.setModuleOn('maintenance', true);
    final soon = DateTime.now().add(const Duration(days: 3));
    await tester.runAsync(
      () => NexModuleStore(h.services, 'maintenance').put('asset', 'a1', {
        'nickname': 'Pride',
        'type': 'car',
        'meterKind': 'none',
        'insuranceExpiresAt': DateTime(
          soon.year,
          soon.month,
          soon.day,
        ).toIso8601String(),
        // Both on one car: two lines, each saying which (2.8.4).
        'inspectionExpiresAt': DateTime(
          soon.year,
          soon.month,
          soon.day,
        ).toIso8601String(),
        'schema': 2,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexToolDates(services: h.services, preferences: h.preferences),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dates from your tools'), findsOneWidget);
    expect(find.text('Pride · Third-party insurance'), findsOneWidget);
    expect(find.text('Pride · Technical inspection'), findsOneWidget);
    expect(find.text('in 3 days'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    // A line opens the module's quick view first (2.8.5).
    await tester.tap(find.text('Pride · Third-party insurance'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('peek-open')), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await h.preferences.setShowToolDates(false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dates from your tools'), findsNothing);
  });

  testWidgets('one module\'s write re-reads only that module\'s dues', (
    tester,
  ) async {
    final h = await NexTestHarness.create(name: 'tool_dates_fanout_');
    addTearDown(h.dispose);
    await h.preferences.setModuleOn('maintenance', true);
    await h.preferences.setModuleOn('occasions', true);
    int readsOf(String module) => h.db.moduleRecordsCalls
        .where((call) => call.startsWith('$module/'))
        .length;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexToolDates(services: h.services, preferences: h.preferences),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final maintenanceBefore = readsOf('maintenance');
    final occasionsBefore = readsOf('occasions');
    expect(maintenanceBefore, greaterThan(0), reason: 'both read when opened');
    expect(occasionsBefore, greaterThan(0));

    // A write to one module: its dues may have moved, the other modules'
    // cannot have. The card used to re-read every enabled module's records
    // for each of these.
    await tester.runAsync(
      () => NexModuleStore(h.services, 'occasions').put('occasion', 'o1', {
        'name': 'A birthday',
        'calendar': 'gregorian',
        'day': '2026-11-20',
        'schema': 2,
      }),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(
      readsOf('maintenance'),
      maintenanceBefore,
      reason: 'a write to occasions cannot move maintenance\'s dues',
    );
    expect(
      readsOf('occasions'),
      greaterThan(occasionsBefore),
      reason: 'the module that wrote is re-read',
    );
  });
}
