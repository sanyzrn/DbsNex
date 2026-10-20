import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// On the second tab a swipe returns to the first; the next swipe goes back.
void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create(name: 'loans_swipe_'));
  tearDown(() => h.dispose());

  for (final rtl in [false, true]) {
    testWidgets('swipe: tab two, tab one, then back (${rtl ? 'RTL' : 'LTR'})', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'lent_borrowed');
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(rtl ? 'fa' : 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nexLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  NexPageRoute<void>(builder: (_) => LoansScreen(store: store)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(LoansScreen), findsOneWidget);

      final tabs = DefaultTabController.maybeOf(
        tester.element(find.byType(TabBarView)),
      );
      final controller =
          tabs ??
          (tester.widget<TabBarView>(find.byType(TabBarView)).controller!);
      controller.animateTo(1);
      await tester.pumpAndSettle();
      expect(controller.index, 1);

      // The way back: toward the end of the line in LTR, the start in RTL.
      final back = Offset(rtl ? -500 : 500, 0);
      // Away from the very edge, so only the page-wide gesture could pop.
      final start = Offset(rtl ? 700 : 100, 300);
      await tester.dragFrom(start, back);
      await tester.pumpAndSettle();
      expect(
        find.byType(LoansScreen),
        findsOneWidget,
        reason: 'first swipe: tab one',
      );
      expect(controller.index, 0);

      await tester.dragFrom(start, back);
      await tester.pumpAndSettle();
      expect(
        find.byType(LoansScreen),
        findsNothing,
        reason: 'next swipe: back',
      );
    });
  }
}
