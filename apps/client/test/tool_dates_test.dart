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
}
