part of 'screen_test.dart';

/// Repair flows for stored history: records a person (or an older
/// version) wrote wrong stay manageable — nothing silently normalizes,
/// nothing becomes unopenable.
void _screenCases3() {
  group('repairing stored history', () {
    testWidgets('a stored offer with a broken date is repaired in the editor', (
      tester,
    ) async {
      await store.put('comparison', 'broken-date', {
        'date': DateTime(2026, 10, 1).toIso8601String(),
        'options': [
          {
            'label': 'Bag 750g',
            'price': 9000,
            'currency': 'IRR',
            'quantity': 750,
            'unit': 'g',
            'packageCount': 1,
            'discount': 'none',
            'date': 'not-a-date',
          },
          {
            'label': 'Bag 1kg',
            'price': 11500,
            'currency': 'IRR',
            'quantity': 1,
            'unit': 'kg',
            'packageCount': 1,
            'discount': 'none',
          },
        ],
        'commonUnit': 'kg',
      });
      await pumpScreen(tester);
      await openMenu(tester);
      await tester.tap(find.text('Saved comparisons'));
      await tester.pumpAndSettle();
      // The calculator is empty, so restoring needs no confirmation.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // The broken offer never produces a ranking…
      expect(
        find.text('An offer is incomplete — open it to fix it'),
        findsAtLeastNWidgets(1),
      );

      // …but it opens for repair, and the broken date is named live.
      await tester.tap(find.text('Bag 750g'));
      await tester.pumpAndSettle();
      expect(find.text('Edit offer'), findsOneWidget);
      expect(
        find.text(
          'Choose a valid shopping date, not in the future — or clear it',
        ),
        findsOneWidget,
      );
      // Clearing is the honest exit; the rest of the offer was fine.
      await tester.ensureVisible(find.text('Clear date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear date'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('An offer is incomplete — open it to fix it'),
        findsNothing,
      );
      expect(find.text('Cheapest per kg'), findsOneWidget);
      expect(find.text('Bag 750g · 120 IRR per kg'), findsOneWidget);
      expect(find.text('Bag 1kg · 115 IRR per kg'), findsOneWidget);
    });
  });
}
