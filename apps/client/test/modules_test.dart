import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/feedback_service.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_plans.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/screens/modules_screen.dart';
import 'package:nex_client/widgets/module_install.dart';
import 'package:nex_ui/nex_ui.dart';

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

  test('every planned module has its words, and is not one already built', () {
    final ids = [for (final plan in nexModulePlans) plan.id];
    expect(ids.toSet(), hasLength(ids.length));
    for (final module in nexModules) {
      expect(ids, isNot(contains(module.id)));
    }
    final titles = <String>{};
    for (final locale in const [Locale('en'), Locale('fa')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final plan in nexModulePlans) {
        expect(plan.title(l10n).trim(), isNotEmpty);
        expect(plan.about(l10n).trim(), isNotEmpty);
        titles.add(plan.title(l10n));
      }
    }
    // The switch falls through to the last plan's words; a new id that was
    // not given its own would show a duplicate title.
    expect(titles, hasLength(nexModulePlans.length * 2));
  });

  test('all modules start off in a fresh install', () {
    expect(nexModulesOn(harness.preferences), isEmpty);
  });

  for (final language in ['en', 'fa']) {
    for (final dark in [false, true]) {
      testWidgets('compact previews and search ($language, dark=$dark)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final l10n = lookupAppLocalizations(Locale(language));
        final cycle = nexModules.first;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: dark ? nexDarkTheme(liquidGlass: true) : nexLightTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: ModulesScreen(
              services: harness.services,
              preferences: harness.preferences,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('module-cycle'));
        final compactHeight = tester.getSize(card).height;
        expect(find.text(cycle.about(l10n)), findsNothing);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, greaterThan(compactHeight));
        expect(find.text(cycle.about(l10n)), findsOneWidget);
        expect(harness.preferences.cycleEnabled, isFalse);
        await tester.tap(find.text(cycle.title(l10n)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('modules-search')),
          'xyznomatch',
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.modulesSearchEmpty), findsOneWidget);
        expect(card, findsNothing);
        final keyword = language == 'en'
            ? cycle.title(l10n).toUpperCase()
            : cycle.title(l10n).replaceAll('ک', 'ك').replaceAll('ی', 'ي');
        await tester.enterText(
          find.byKey(const ValueKey('modules-search')),
          keyword,
        );
        await tester.pumpAndSettle();
        expect(card, findsOneWidget);
        expect(find.byKey(const ValueKey('module-habits')), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('modules-search')),
          language == 'fa' ? 'اذان' : 'prayer',
        );
        await tester.pumpAndSettle();
        final calendar = find.byKey(const ValueKey('plan-persian-calendar'));
        expect(calendar, findsOneWidget);
        expect(
          find.descendant(
            of: calendar,
            matching: find.text(l10n.moduleStageSoon),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: calendar,
            matching: find.byType(ButtonStyleButton),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

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
      final card = find.byKey(
        ValueKey('${module.available ? 'module' : 'plan'}-${module.id}'),
      );
      await tester.scrollUntilVisible(
        card,
        400,
        maxScrolls: 40,
        scrollable: find.byType(Scrollable).first,
      );
      expect(card, findsOneWidget);
      expect(find.byKey(ValueKey('module-${module.id}-add')), findsNothing);
    }
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();

    await harness.preferences.setCycleEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('Nothing added yet'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('module-cycle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-cycle-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('module-cycle-remove')), findsOneWidget);
    // Added above Available.
    expect(
      tester.getTopLeft(find.text('Added')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('module-cycle'))).dy,
      ),
    );

    // What is coming is listed under it, with a badge and no button.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plan-telegram')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plan-telegram')),
        matching: find.text('Soon'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plan-telegram')),
        matching: find.byType(ButtonStyleButton),
      ),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('modules-suggest')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Have an idea for a module? Tell us'), findsOneWidget);

    // It opens a sheet for the idea alone: no kind to pick, nothing to
    // attach.
    await tester.tap(find.byKey(const ValueKey('modules-suggest')));
    await tester.pumpAndSettle();
    expect(find.text('An idea for a module'), findsOneWidget);
    expect(find.byKey(const ValueKey('module-idea-send')), findsOneWidget);
    expect(find.byType(SegmentedButton<FeedbackKind>), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets(
    'adding is an installation you can watch, and removing undoes it',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      final prefs = harness.preferences;

      await tester.tap(find.byKey(const ValueKey('module-cycle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('module-cycle-add')));
      await tester.pump();
      await tester.pump(moduleInstallTime ~/ 2);
      // Mid-way: the bar and its step stand where the button was, and the
      // module is not part of the app until the run is over.
      expect(find.byType(ModuleInstallProgress), findsOneWidget);
      expect(find.text('Setting up'), findsOneWidget);
      expect(find.byKey(const ValueKey('module-cycle-add')), findsNothing);
      expect(prefs.cycleEnabled, isFalse);

      await tester.pumpAndSettle();
      expect(prefs.cycleEnabled, isTrue);
      expect(find.byType(ModuleInstallProgress), findsNothing);
      expect(find.byKey(const ValueKey('module-cycle-open')), findsOneWidget);
      expect(find.text('Cycle is in Tools now'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('module-cycle-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-off-keep')));
      await tester.pump();
      await tester.pump();
      await tester.pump(moduleRemoveTime ~/ 4);
      // Taken apart where it stood, among the added, before it moves.
      expect(prefs.cycleEnabled, isFalse);
      expect(find.text('Removing from Tools'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Added')).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('module-cycle'))).dy,
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('module-cycle-add')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('module-cycle'))).dy,
        greaterThan(tester.getTopLeft(find.text('Available')).dy),
      );
      expect(find.text('Cycle removed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('with animations removed, adding is immediate', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ModulesScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('module-cycle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('module-cycle-add')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(harness.preferences.cycleEnabled, isTrue);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });
}
