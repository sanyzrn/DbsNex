import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_review_page.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'words_compact_'),
  );
  tearDown(() => harness.dispose());
  for (final locale in [const Locale('en'), const Locale('fa')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'compact review ${locale.languageCode} $brightness with long text and reduced motion',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final store = NexModuleStore(harness.services, 'words');
          await store.put(
            'card',
            'x',
            WordCard(
              id: 'x',
              headword: List.filled(25, 'A longer phrase').join(' '),
              language: 'English',
              meaning: List.filled(20, 'معنای واردشده').join(' '),
              createdAtIso: '2026-10-13T12:00:00',
            ).toRecord(),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: WordsReviewPage(store: store),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('words-review-card')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('words-answer-good')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect((await store.get('card', 'x'))!['reps'], 1);
          await tester.ensureVisible(
            find.byKey(const ValueKey('words-schedule-how')),
          );
          await tester.tap(find.byKey(const ValueKey('words-schedule-how')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
