import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/changelog_panel.dart';

void main() {
  testWidgets(
    'shows real bullets from the bundled CHANGELOG.md, not a network fetch',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ChangelogPanel()),
        ),
      );
      // `rootBundle.loadString` is real file IO — it does not reliably resolve
      // inside `pumpAndSettle`'s fake-async pumping alone.
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      // A real, specific bullet from the file's current "Unreleased" section —
      // proves the asset actually loaded and parsed, not just that the panel
      // rendered without crashing.
      expect(find.text('Latest changes'), findsOneWidget);
      expect(
        find.text('Toasts pop in instead of just fading.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'parseChangelogSections splits on ## headings and drops the preamble',
    (tester) async {
      const raw = '''
# Changelog

## How this file is used

Notes for contributors, not for the app.

## Unreleased

- newest bullet

## v0.1.0

- older bullet
''';
      final sections = parseChangelogSections(raw);

      expect(sections.map((s) => s.heading), ['Unreleased', 'v0.1.0']);
      expect(sections[0].body, '- newest bullet');
      expect(sections[1].body, '- older bullet');
    },
  );

  test('a section with a heading but no bullets is dropped', () {
    const raw = '''
## Unreleased

## v0.1.0

- kept
''';
    final sections = parseChangelogSections(raw);

    expect(sections, hasLength(1));
    expect(sections.single.heading, 'v0.1.0');
  });
}
