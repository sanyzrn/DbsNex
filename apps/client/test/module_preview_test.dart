import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_registry.dart';
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
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_preview_'),
  );
  tearDown(() => harness.dispose());

  test('all modules default off, including the eleven add-ons', () {
    expect(moduleIds, hasLength(11));
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
      expect(nexModulesOn(reloaded), hasLength(10));
      await reloaded.setModuleOn('habits', true);
      expect(nexModulesOn(reloaded), hasLength(11));
    },
  );

  test(
    'identical record keys stay isolated across all eleven modules',
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
    testWidgets('all eleven open from Tools and return ($locale)', (
      tester,
    ) async {
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
      for (final id in moduleIds) {
        final tile = find.byKey(ValueKey('tool-module.$id'));
        await tester.scrollUntilVisible(tile, 350, maxScrolls: 30);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(ToolsScreen).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull, reason: id);
        expect(find.byType(BackButton), findsOneWidget, reason: '$locale:$id');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(ToolsScreen), findsOneWidget);
      }
      expect(await harness.services.timeline(), isEmpty);
    });
  }
}
