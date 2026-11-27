import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/model.dart';
import 'package:nex_client/modules/cheques/month_view.dart';

import 'fixtures.dart';

import 'package:nex_client/modules/cheques/privacy.dart';

/// The month view lists only the days something falls due, and marks one
/// where more goes out than comes in (2.8.4) — no longer a card for every
/// day of the month, most of them empty.
void main() {
  Future<void> show(WidgetTester tester, List<Cheque> rows) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChequePrivacy(
          child: Scaffold(
            appBar: AppBar(actions: const [ChequePrivacyButton()]),
            body: ChequeMonth(
              rows: rows,
              month: DateTime(2026, 11, 20),
              move: (_) {},
              open: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder days() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('cheque-month-day-'),
  );

  testWidgets('two days with cheques, two cards; the paying one marked', (
    tester,
  ) async {
    await show(tester, [
      Cheque('a', chequeRaw(direction: 'outgoing', date: '2026-11-10')),
      Cheque('b', chequeRaw(direction: 'incoming', date: '2026-11-15')),
    ]);
    expect(days(), findsNWidgets(2));
    expect(find.byIcon(Icons.south_east), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding amounts also masks the direction of net cash flow', (
    tester,
  ) async {
    await show(tester, [Cheque('a', chequeRaw(date: '2026-11-10'))]);
    expect(find.byIcon(Icons.south_east), findsOneWidget);
    await tester.tap(find.byTooltip('Hide amounts'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.south_east), findsNothing);
    expect(find.textContaining('−••••'), findsNothing);
    expect(days(), findsOneWidget);
  });

  testWidgets('a month with nothing due says so once', (tester) async {
    await show(tester, const []);
    expect(days(), findsNothing);
  });
}
