import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_plans.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/screens/module_settings_screen.dart';
import 'package:nex_client/screens/module_shelves.dart';
import 'package:nex_client/screens/modules_screen.dart';
import 'package:nex_client/screens/tools_screen.dart';

import 'support/nex_harness.dart';

/// Tools and modules, arranged (2.8.3): pins in plain sight and in an order
/// of one's own, modules in the order one wants them, shelves to narrow the
/// Modules page, the one action on a closed card, and "I want this" on what
/// is still to come.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_arr_'));
  tearDown(() => harness.dispose());

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 2400);
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
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Tools has Arrange; a pin there is one tap, and what is on '
      'home is listed first', (tester) async {
    final prefs = harness.preferences;
    await prefs.setModuleOn('gold', true);
    await show(
      tester,
      ToolsScreen(services: harness.services, preferences: prefs),
    );
    await tester.tap(find.byKey(const ValueKey('tools-arrange')));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleSettingsScreen), findsOneWidget);
    expect(find.text('On your home screen'), findsOneWidget);
    expect(find.textContaining('Nothing is pinned yet'), findsOneWidget);

    // Gold, from "Your modules", onto the home screen.
    final gold = find.byKey(const ValueKey('arrange-modules-module.gold'));
    expect(gold, findsOneWidget);
    await tester.tap(
      find.descendant(of: gold, matching: find.byTooltip('Pin to home')),
    );
    await tester.pumpAndSettle();
    expect(prefs.pinnedTools, ['module.gold']);
    expect(
      find.byKey(const ValueKey('arrange-home-module.gold')),
      findsOneWidget,
    );
  });

  testWidgets('dragging puts pinned tools and modules in a new order', (
    tester,
  ) async {
    final prefs = harness.preferences;
    for (final id in ['gold', 'words', 'habits']) {
      await prefs.setModuleOn(id, true);
    }
    await prefs.setPinnedTools(['module.gold', 'module.words']);
    expect(prefs.pinnedTools, ['module.gold', 'module.words']);
    await show(
      tester,
      ModuleSettingsScreen(services: harness.services, preferences: prefs),
    );
    final handle = find.descendant(
      of: find.byKey(const ValueKey('arrange-home-module.words')),
      matching: find.byIcon(Icons.drag_indicator),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(prefs.pinnedTools, ['module.words', 'module.gold']);

    // The modules' order is kept by id and followed everywhere.
    await prefs.setModuleOrder(['habits', 'gold']);
    final ordered = [
      for (final m in nexModulesInOrder(nexModulesOn(prefs), prefs)) m.id,
    ];
    expect(ordered, ['habits', 'gold', 'words']);
  });

  testWidgets('Modules: a count, shelves that narrow it, and Add on the '
      'closed card', (tester) async {
    final prefs = harness.preferences;
    await show(
      tester,
      ModulesScreen(services: harness.services, preferences: prefs),
    );
    final available = nexModules.where((m) => m.available).length;
    expect(find.text('None added · $available to add'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('modules-shelf-money')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-gold')), findsOneWidget);
    expect(find.byKey(const ValueKey('module-words')), findsNothing);
    expect(nexModuleCategory('gold'), 'money');
    expect(nexModuleCategory('somebody_elses'), 'everyday');

    await tester.tap(find.byKey(const ValueKey('module-gold-quick-add')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(prefs.isModuleOn('gold'), isTrue);
    expect(find.byKey(const ValueKey('module-gold-go')), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('a module still to come can be wanted, and said so', (
    tester,
  ) async {
    final prefs = harness.preferences;
    final plan = nexModulePlans.first;
    await show(
      tester,
      ModulesScreen(services: harness.services, preferences: prefs),
    );
    final want = find.byKey(ValueKey('plan-${plan.id}-want'));
    await tester.scrollUntilVisible(
      want,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: want, matching: find.text('I want this')),
      findsOneWidget,
    );
    await tester.ensureVisible(want);
    await tester.pumpAndSettle();
    await tester.tap(want);
    await tester.pumpAndSettle();
    expect(prefs.wantedModules, {plan.id});
    expect(find.text('Tell them'), findsOneWidget);
    expect(
      find.descendant(of: want, matching: find.text('You want this')),
      findsOneWidget,
    );
    await tester.tap(want);
    await tester.pumpAndSettle();
    expect(prefs.wantedModules, isEmpty);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });
}
