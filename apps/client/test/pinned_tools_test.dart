import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/platform/vault_session.dart';
import 'package:nex_client/screens/tools/pinned_tools.dart';
import 'package:nex_client/screens/tools_screen.dart';
import 'package:nex_client/widgets/nex_shelf.dart';

import 'support/nex_harness.dart';

/// A tool held on the Tools page goes to the top of the timeline, in its own
/// colour and icon, and a hold there takes it off again.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_pinned_tools_');
  });
  tearDown(() => harness.dispose());

  Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a hold on the Tools page pins and unpins, with a way back', (
    tester,
  ) async {
    await tall(tester);
    await tester.pumpWidget(
      host(
        ToolsScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('tool-generator')));
    await tester.pumpAndSettle();
    expect(harness.preferences.pinnedTools, ['generator']);
    expect(find.text('Pinned to the home screen'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('tool-vault.card')));
    await tester.pumpAndSettle();
    expect(harness.preferences.pinnedTools, ['generator', 'vault.card']);

    await tester.longPress(find.byKey(const ValueKey('tool-generator')));
    await tester.pumpAndSettle();
    expect(harness.preferences.pinnedTools, ['vault.card']);
  });

  for (final locale in ['en', 'fa']) {
    testWidgets('pinned tools show as cards, and a hold takes one off '
        '($locale)', (tester) async {
      await harness.preferences.togglePinnedTool('vault.password');
      await harness.preferences.togglePinnedTool('generator');
      // A pin whose tool is gone is not drawn — a module removed, or
      // Scheduled, which moved to the Library in 2.3.4.
      await harness.preferences.togglePinnedTool('module.gone');
      await harness.preferences.togglePinnedTool('scheduled');
      await tester.pumpWidget(
        host(
          PinnedTools(
            services: harness.services,
            preferences: harness.preferences,
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pinned-tool-vault.password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pinned-tool-generator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pinned-tool-module.gone')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pinned-tool-scheduled')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.longPress(
        find.byKey(const ValueKey('pinned-tool-generator')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pinned-tool-generator')), findsNothing);
      expect(harness.preferences.pinnedTools, isNot(contains('generator')));
    });
  }

  testWidgets('one or two tiles share the row; from three on it scrolls '
      'sideways with the next one showing', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Finder tile(String id) => find.byKey(ValueKey('pinned-tool-$id'));
    final rail = find.byKey(const ValueKey('glance-rail'));
    Future<void> show() async {
      await tester.pumpWidget(
        host(
          PinnedTools(
            services: harness.services,
            preferences: harness.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await harness.preferences.togglePinnedTool('generator');
    await harness.preferences.togglePinnedTool('vault.card');
    await show();
    // Two: side by side, edge to edge of the page's own gutters, level.
    final first = tester.getRect(tile('generator'));
    final second = tester.getRect(tile('vault.card'));
    expect(first.top, second.top);
    expect(first.width, closeTo(second.width, 0.5));
    expect(first.left, closeTo(16, 0.5));
    expect(second.right, closeTo(412 - 16, 0.5));
    final scroll = tester.widget<SingleChildScrollView>(rail);
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: rail, matching: find.byType(Scrollable)),
          )
          .position
          .maxScrollExtent,
      0,
      reason: 'two tiles fit: nothing to scroll',
    );

    // Three: still one row — it used to be two rows, the odd one out alone
    // on the second — and the third shows its edge at the side.
    await harness.preferences.togglePinnedTool('vault.password');
    await show();
    final rects = [
      for (final id in ['generator', 'vault.card', 'vault.password'])
        tester.getRect(tile(id)),
    ];
    expect({for (final rect in rects) rect.top}, hasLength(1));
    expect(rects[1].right, lessThan(412));
    expect(rects[2].left, lessThan(412), reason: 'the next one peeks in');
    expect(rects[2].right, greaterThan(412));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: rail, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(rail, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(tile('vault.password')).right,
      closeTo(412 - 16, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a module that counts toward something draws it as a ring', (
    tester,
  ) async {
    await harness.preferences.setModuleOn('habits', true);
    final now = DateTime.now();
    final store = NexModuleStore(harness.services, 'habits');
    for (final id in ['water', 'walk']) {
      await store.put('habit', id, {
        'name': id,
        'schedule': 'daily',
        'goal': 1,
        'archived': false,
        'createdAt': now.subtract(const Duration(days: 10)).toIso8601String(),
      });
    }
    await store.put('check', HabitCheck.idFor('water', dateKeyOf(now)), {
      'habit': 'water',
      'date': dateKeyOf(now),
      'amount': 1,
      'at': now.toIso8601String(),
    });
    await harness.preferences.togglePinnedTool('module.habits');
    await harness.preferences.togglePinnedTool('generator');
    await tester.pumpWidget(
      host(
        PinnedTools(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    NexProgressRing ring(String id) => tester.widget<NexProgressRing>(
      find.descendant(
        of: find.byKey(ValueKey('pinned-tool-$id')),
        matching: find.byType(NexProgressRing),
      ),
    );
    // One habit of two done today: half the ring, a real count.
    expect(ring('module.habits').progress, 0.5);
    // A tool that counts nothing keeps the ring's room and draws none, so
    // the marks along the row stay level.
    expect(ring('generator').progress, isNull);
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('pinned-tool-module.habits')),
          matching: find.byType(NexProgressRing),
        ),
      ),
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('pinned-tool-generator')),
          matching: find.byType(NexProgressRing),
        ),
      ),
    );
  });

  testWidgets('nothing at all while hidden', (tester) async {
    await harness.preferences.togglePinnedTool('generator');
    await tester.pumpWidget(
      host(
        PinnedTools(
          services: harness.services,
          preferences: harness.preferences,
          hidden: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pinned-tool-generator')), findsNothing);
  });

  // The lock opens with the private tools and closes again with them —
  // when they are locked by hand and when the unlock runs out.
  testWidgets("a private tool's lock opens while the vault is unlocked", (
    tester,
  ) async {
    final session = VaultSession.instance;
    var now = DateTime(2026, 10, 13, 9);
    session.clock = () => now;
    addTearDown(() {
      session.close();
      session.clock = DateTime.now;
    });
    await harness.preferences.togglePinnedTool('vault.card');
    await tester.pumpWidget(
      host(
        PinnedTools(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    session.open();
    await tester.pump();
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);

    session.close();
    await tester.pump();
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    session.open();
    await tester.pump();
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    now = now.add(VaultSession.grace + const Duration(seconds: 1));
    await tester.pump(VaultSession.grace + const Duration(seconds: 1));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });
}
