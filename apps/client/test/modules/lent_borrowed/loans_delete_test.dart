import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'loans_test_tools.dart';

/// Deletion with Undo that restores everything, and the data outliving the
/// screen that shows it.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_lent_'));
  tearDown(() => harness.dispose());

  group('deleting with Undo', () {
    testWidgets('Undo restores the record with its whole return history', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '200000',
      );
      final returnSave = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(returnSave);
      await tester.pumpAndSettle();
      await tester.tap(returnSave);
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('loan-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete record'));
      await settleLoans(tester);

      expect(await store.list('loan'), isEmpty);
      expect(await store.list('return'), isEmpty);
      expect(find.text('Record deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settleLoans(tester);

      expect(await store.list('loan'), hasLength(1));
      expect(
        await store.list('return'),
        hasLength(1),
        reason: 'the return history came back too',
      );
      expect(
        find.textContaining('300,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
    });
  });

  group('the screen is a window, not the data', () {
    testWidgets('records survive disposing and re-opening the screen', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final reopened = NexModuleStore(harness.services, 'lent_borrowed');
      expect(await reopened.list('loan'), hasLength(1));

      await tester.pumpWidget(pumpableLoansScreen(reopened));
      await tester.pumpAndSettle();
      expect(find.text('Ali'), findsOneWidget);
    });

    testWidgets('another module’s store cannot see these records', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      final stranger = NexModuleStore(harness.services, 'habits');
      expect(await stranger.list('loan'), isEmpty);
      expect(await stranger.list('return'), isEmpty);
    });
  });
}
