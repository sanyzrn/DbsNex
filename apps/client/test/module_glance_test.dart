import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/modules/module_shared.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/nex_stored_module.dart';
import 'package:nex_client/modules/parking/parking_models.dart';
import 'package:nex_client/widgets/module_peek.dart';

import 'support/nex_harness.dart';

/// 2.8.5: every module says what it holds at a glance, and a tap on its
/// pinned tile opens a quick view before the module.
void main() {
  final l10n = AppLocalizationsEn();
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create(name: 'glance_'));
  tearDown(() => h.dispose());

  NexStoredModule module(String id) => nexModulesById[id]! as NexStoredModule;
  NexModuleStore store(String id) => NexModuleStore(h.services, id);

  test('every folder module has a glance, empty or not', () async {
    for (final m in nexModules.whereType<NexStoredModule>()) {
      final glance = await m.glance(store(m.id), l10n, DateTime.now());
      expect(glance, isNotNull, reason: m.id);
      expect(glance!.headline.trim(), isNotEmpty, reason: m.id);
    }
  });

  test('a parked car is on its tile: where it is and the time left', () async {
    final now = DateTime(2026, 11, 18, 10);
    await store('parking').put(
      ParkingModels.session,
      's1',
      ParkingModels.sessionBody(
        vehicle: 'Pride',
        place: 'Tirajeh mall',
        floor: '-2',
        spot: 'B14',
        landmark: 'by the lifts',
        startedAt: now.subtract(const Duration(minutes: 40)),
        expiresAt: now.add(const Duration(minutes: 80)),
      ),
    );
    final glance = (await module('parking')
        .glance(store('parking'), l10n, now))!;
    expect(glance.headline, 'Tirajeh mall · -2 · B14');
    expect(glance.detail, '1 h 20 min left');
    expect(glance.facts.map((f) => f.value), contains('by the lifts'));
  });

  test('the asset book stays covered on the home screen', () async {
    final glance = (await module('assets')
        .glance(store('assets'), l10n, DateTime.now()))!;
    expect(glance.facts, isEmpty);
    expect(glance.headline, 'Your book is covered');
  });

  test('habits left today are one line on the dates card, said in the '
      'page\'s language', () async {
    for (final name in ['Read', 'Walk']) {
      await store('habits').put('habit', name, {
        'name': name,
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': false,
        'createdAt': DateTime.now()
            .subtract(const Duration(days: 4))
            .toIso8601String(),
      });
    }
    final today = DateTime.now();
    final dues = await module('habits').dues(
      store('habits'),
      today.subtract(const Duration(days: 60)),
      today.add(const Duration(days: 8)),
    );
    expect(dues, hasLength(1));
    expect(dues.single.title, isEmpty);
    expect(
      module('habits').dueLabel(l10n, dues.single.kind),
      '2 habits left for today',
    );
  });

  testWidgets('the quick view shows the glance and opens the module', (
    tester,
  ) async {
    await h.preferences.setModuleOn('parking', true);
    final now = DateTime.now();
    await tester.runAsync(
      () => store('parking').put(
        ParkingModels.session,
        's1',
        ParkingModels.sessionBody(
          vehicle: '',
          place: 'Office',
          floor: '',
          spot: '',
          landmark: '',
          startedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => nexShowModulePeek(
                context,
                module: module('parking'),
                services: h.services,
                preferences: h.preferences,
              ),
              child: const Text('tile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tile'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ModulePeek), findsOneWidget);
    expect(find.text('Office'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('peek-open')));
    await tester.pumpAndSettle();
    expect(find.byType(ModulePeek), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a dose not taken before today is not left to do', () async {
    final medicine = module('medicine');
    final today = DateTime.now();
    final dues = await medicine.dues(
      store('medicine'),
      today.subtract(const Duration(days: 60)),
      today.add(const Duration(days: 8)),
    );
    expect(
      dues.where(
        (d) =>
            d.kind == 'dose' &&
            d.at.isBefore(DateTime(today.year, today.month, today.day)),
      ),
      isEmpty,
    );
  });

  test('nexTomanText groups whole tomans and keeps a tenth', () {
    expect(nexTomanText(BigInt.from(125000), l10n), '12,500 toman');
    expect(nexTomanText(BigInt.from(125005), l10n), '12,500.5 toman');
  });
}
