import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app_version.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/whats_new_screen.dart';
import 'package:nex_ui/nex_ui.dart';

/// "What's new": the bundled changelog, every release, opened from About.
void main() {
  test('a release section becomes titled items', () {
    const raw = '''
## Unreleased

## v9.9.9

- **Bells.** A reminder rings on its card.
- A plain line
  that wraps.

## v9.9.8

An opening paragraph.

- **Old.** Not this one.
''';
    final items = whatsNewItems(raw, '9.9.9');
    expect(items, hasLength(2));
    expect(items.first.title, 'Bells');
    expect(items.first.body, 'A reminder rings on its card.');
    expect(items.last.title, isEmpty);
    expect(items.last.body, 'A plain line that wraps.');
    final all = parseWhatsNewReleases(raw);
    expect(all.map((r) => r.version), ['9.9.9', '9.9.8']);
    expect(all.last.intro, 'An opening paragraph.');
  });

  test('Persian notes where they exist, English before them', () {
    final en = parseWhatsNewReleases(
      '## v2.0.0\n\n- **A.** a\n\n## v1.0.0\n\n- **B.** b\n',
    );
    final fa = parseWhatsNewReleases('## v2.0.0\n\n- **الف.** ا\n');
    final merged = mergeWhatsNew(en, fa);
    expect(merged.first.items.single.title, 'الف');
    expect(merged.last.items.single.title, 'B');
  });

  test('this version has notes in both languages', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final file in ['assets/CHANGELOG.md', 'assets/CHANGELOG.fa.md']) {
      final raw = await rootBundle.loadString(file);
      expect(whatsNewItems(raw, nexAppVersion), isNotEmpty, reason: file);
    }
  });

  for (final lang in ['en', 'fa']) {
    for (final dark in [false, true]) {
      testWidgets('the page lists every release and searches them '
          '($lang, ${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? nexDarkTheme() : nexLightTheme(),
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WhatsNewScreen(),
          ),
        );
        // The bundled changelog is read for real: wait for it, however long
        // the machine takes.
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (find.byType(ListView).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whats-new-0.9.1')),
          1500,
          maxScrolls: 400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('whats-new-0.9.1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Back to the top in one jump: dragging up past ninety thousand
        // pixels of history is not what this test is about.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('whats-new-search')),
          'zzqqxx',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('whats-new-0.9.1')), findsNothing);
      });
    }
  }
}
