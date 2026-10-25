import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// 2.3.1: a recurring item's reminder opens the Recurring page, not the home
/// screen — from a new notification, and from one shown before 2.3.1 whose
/// payload was the item's bare id.
void main() {
  for (final old in [false, true]) {
    testWidgets('a tapped recurring reminder opens its page'
        '${old ? ' (shown before 2.3.1)' : ''}', (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.services.saveCommitment(
        NexCommitment(
          id: 'rent',
          title: 'pay the rent',
          cadence: NexCadence.months,
          every: 1,
          dueAt: DateTime(2030, 1, 1, 9),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(find.byType(RecurringScreen), findsNothing);
      if (old) {
        h.services.reminders.onOpenNote!('rent');
      } else {
        h.services.reminders.onOpenRecurring!();
      }
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(RecurringScreen).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(RecurringScreen), findsOneWidget);
      expect(find.text('pay the rent'), findsWidgets);
      h.services.ringing.value = const {};
      await tester.pumpWidget(const SizedBox());
    });
  }
}
