import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
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
}
