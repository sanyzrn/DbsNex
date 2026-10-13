import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/vault_session.dart';
import 'package:nex_client/screens/tools/pinned_tools.dart';
import 'package:nex_client/screens/tools_screen.dart';

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
      await harness.preferences.togglePinnedTool('scheduled');
      // A pin whose tool is gone is not drawn.
      await harness.preferences.togglePinnedTool('module.gone');
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
        find.byKey(const ValueKey('pinned-tool-scheduled')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pinned-tool-module.gone')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.longPress(
        find.byKey(const ValueKey('pinned-tool-scheduled')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pinned-tool-scheduled')), findsNothing);
      expect(harness.preferences.pinnedTools, isNot(contains('scheduled')));
    });
  }

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
