import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_daily_cap.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_store.dart';

import '../../support/nex_harness.dart';

/// The daily and per-session caps are chosen in the app's own dialog (2.6.27)
/// — it was a stock SimpleDialog — and the choice is saved.
void main() {
  for (final locale in ['en', 'fa']) {
    for (final session in [false, true]) {
      testWidgets('$locale session=$session: pick a cap and it is saved', (
        tester,
      ) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        final repository = WordsRepository(NexModuleStore(h.services, 'words'));
        const settings = WordsSettings(newPerDay: 10, sessionLimit: 20);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            theme: nexSoftLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: WordsDailyCapRow(
                  settings: settings,
                  repository: repository,
                  session: session,
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(
            ValueKey(session ? 'words-session-cap' : 'words-daily-cap'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NexAlertDialog), findsOneWidget);
        expect(find.byType(SimpleDialog), findsNothing);
        // The current value is the ticked row.
        final current = find.byKey(
          ValueKey(session ? 'words-session-cap-20' : 'words-cap-10'),
        );
        expect(tester.widget<ListTile>(current).selected, isTrue);
        expect(tester.getSize(current).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(
            ValueKey(session ? 'words-session-cap-40' : 'words-cap-0'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NexAlertDialog), findsNothing);
        final saved = await tester.runAsync(repository.loadSettings);
        if (session) {
          expect(saved!.sessionLimit, 40);
        } else {
          expect(saved!.newPerDay, 0);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
