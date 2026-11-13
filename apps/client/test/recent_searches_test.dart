import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/note_search.dart';
import 'package:nex_client/widgets/search_results.dart';

import 'support/nex_harness.dart';

/// The last few searches come back as chips on the empty search screen.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_recent_searches_');
  });
  tearDown(() => harness.dispose());

  test('newest first, no repeats, no stray letters, five at most', () async {
    final preferences = harness.preferences;
    for (final query in ['boiler', 'a', 'invoice', 'boiler', ' tax ']) {
      await preferences.rememberSearch(query);
    }
    expect(preferences.recentSearches, ['tax', 'boiler', 'invoice']);
    for (var i = 0; i < 8; i++) {
      await preferences.rememberSearch('query $i');
    }
    expect(preferences.recentSearches, hasLength(5));
    expect(preferences.recentSearches.first, 'query 7');
    await preferences.clearRecentSearches();
    expect(preferences.recentSearches, isEmpty);
  });

  testWidgets('a chip searches again, and Clear forgets them all', (
    tester,
  ) async {
    final preferences = harness.preferences;
    await preferences.rememberSearch('boiler');
    await preferences.rememberSearch('قبض برق');
    await preferences.saveSearch('boiler');
    final search = NoteSearchController(services: harness.services);
    addTearDown(search.dispose);
    final used = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => CustomScrollView(
              slivers: searchResultSlivers(
                context: context,
                search: search,
                preferences: preferences,
                onOpen: (_) {},
                onUseSaved: used.add,
              ),
            ),
          ),
        ),
      ),
    );

    // A search that is kept is shown once, among the kept ones.
    expect(find.byKey(const ValueKey('recent-search-boiler')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recent-search-قبض برق')));
    expect(used, ['قبض برق']);

    await tester.tap(find.byKey(const ValueKey('recent-searches-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsNothing);
    expect(preferences.recentSearches, isEmpty);
  });

  testWidgets('on the search screen, a chip runs its search and stays', (
    tester,
  ) async {
    // The report (2.6.27): touching a recent search closed search instead.
    // With the field empty, a touch outside the search leaves it, and the
    // chips were not counted as part of the search.
    await harness.services.captureText('boiler service on Friday');
    await harness.services.captureText('something else');
    await harness.preferences.rememberSearch('boiler');
    await tester.pumpWidget(harness.app());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('recent-search-boiler'));
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'boiler', reason: 'still searching');
    expect(find.textContaining('boiler service'), findsWidgets);
    expect(find.textContaining('something else'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
