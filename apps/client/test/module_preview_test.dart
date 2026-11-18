import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/modules/module_rollout.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/tools_screen.dart';

import 'support/nex_harness.dart';

void main() {
  final moduleIds = nexModules
      .whereType<NexStoredModule>()
      .map((m) => m.id)
      .toSet();
  // Only the ones listed in module_rollout.dart are available (Cycle, which is
  // not a stored add-on); the add-ons are Soon again until each is finished.
  final reviewed = moduleIds.where(nexModuleAvailable).toSet();
  final paused = moduleIds.difference(reviewed);
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_preview_'),
  );
  tearDown(() => harness.dispose());

  test('fifteen add-ons are back, the other one is Soon; their code '
      'stays', () {
    // Cycle; Pause, which is first-party; and the add-ons reviewed and turned
    // on since 2.4.0 — five more of them in 2.8.1.
    const back = {
      'occasions',
      'words',
      'habits',
      'converter',
      'warranty',
      'gold',
      'smoke_free',
      'lent_borrowed',
      'prompt_studio',
      'security_tools',
      // 2.8.4.
      'parking',
      'medicine',
      'cheques',
      'maintenance',
      'expenses',
    };
    expect(nexAvailableModuleIds, {'cycle', 'pause', ...back});
    expect(reviewed, back);
    expect(paused, moduleIds.difference(back));
    // The existing add-ons plus the new Cheques module, still Soon.
    expect(
      moduleIds,
      containsAll(['prompt_studio', 'security_tools', 'cheques']),
    );
    expect(moduleIds, hasLength(16));
  });

  test(
    'a paused add-on keeps its installation choice and is not active',
    () async {
      await harness.preferences.setModuleOn('price_lens', true);
      expect(harness.preferences.isModuleOn('price_lens'), isTrue);
      expect(nexModulesOn(harness.preferences), isEmpty);
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.isModuleOn('price_lens'), isTrue);
    },
  );

  test('all modules default off, including the sixteen add-ons', () {
    expect(moduleIds, hasLength(16));
    expect(
      nexModules.whereType<NexStoredModule>().map((m) => m.id).toSet(),
      moduleIds,
    );
    expect(nexModulesOn(harness.preferences), isEmpty);
    expect(harness.preferences.cycleEnabled, isFalse);
    expect(harness.preferences.isModuleOn('future_module'), isFalse);
  });

  test(
    'removing a preview module survives reload without disabling others',
    () async {
      for (final id in moduleIds) {
        await harness.preferences.setModuleOn(id, true);
      }
      await harness.preferences.setModuleOn('habits', false);
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.isModuleOn('habits'), isFalse);
      for (final id in moduleIds.difference({'habits'})) {
        expect(reloaded.isModuleOn(id), isTrue, reason: id);
      }
      await reloaded.setModuleOn('habits', true);
      for (final id in moduleIds) {
        expect(reloaded.isModuleOn(id), isTrue, reason: id);
      }
    },
  );

  test(
    'identical record keys stay isolated across all stored modules',
    () async {
      for (final id in moduleIds) {
        await NexModuleStore(
          harness.services,
          id,
        ).put('sample', 'same-id', {'owner': id});
      }
      await harness.services.moduleDeleteAll('habits');
      for (final id in moduleIds) {
        expect(
          await NexModuleStore(harness.services, id).get('sample', 'same-id'),
          id == 'habits' ? isNull : {'owner': id},
        );
      }
      expect(await harness.services.timeline(), isEmpty);
      expect(await harness.services.cyclePeriods(), isEmpty);
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets('every add-on has a Tools entry ($locale)', (tester) async {
      for (final id in moduleIds) {
        await harness.preferences.setModuleOn(id, true);
      }
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: locale == 'fa'
              ? nexDarkTheme(liquidGlass: true)
              : nexLightTheme(),
          home: ToolsScreen(
            services: harness.services,
            preferences: harness.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        nexModulesOn(harness.preferences).map((m) => m.id).toSet(),
        reviewed,
      );
      for (final id in moduleIds) {
        expect(harness.preferences.isModuleOn(id), isTrue);
        expect(
          find.byKey(ValueKey('tool-module.$id')),
          reviewed.contains(id) ? findsOneWidget : findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
      expect(await harness.services.timeline(), isEmpty);
    });
  }
}
