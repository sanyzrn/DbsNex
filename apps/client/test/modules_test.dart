import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/screens/modules_screen.dart';

import 'support/nex_harness.dart';

/// The module platform (ADR-040, `docs/17-modules.md`).
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_mod_'));
  tearDown(() => harness.dispose());

  test('every module has its own stable, lower-case id', () {
    final ids = [for (final m in nexModules) m.id];
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
    }
  });

  test('a new module is off until added, one key each', () async {
    final prefs = harness.preferences;
    expect(prefs.isModuleOn('planner'), isFalse);
    await prefs.setModuleOn('planner', true);
    expect(prefs.isModuleOn('planner'), isTrue);
    expect(prefs.isModuleOn('water'), isFalse);
  });

  test('nothing is on in a fresh install', () {
    expect(nexModulesOn(harness.preferences), isEmpty);
  });

  testWidgets('the page lists every module, added ones first', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ModulesScreen(
            services: harness.services,
            preferences: harness.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.text('Nothing added yet'), findsOneWidget);
    for (final module in nexModules) {
      expect(find.byKey(ValueKey('module-${module.id}-add')), findsOneWidget);
    }

    await harness.preferences.setCycleEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('Nothing added yet'), findsNothing);
    expect(find.byKey(const ValueKey('module-cycle-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('module-cycle-remove')), findsOneWidget);
    // Added above Available.
    expect(
      tester.getTopLeft(find.text('Added')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('module-cycle'))).dy,
      ),
    );
  });
}
