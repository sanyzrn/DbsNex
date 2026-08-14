import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/changelog_panel.dart';

void main() {
  test(
    "the bundled asset copy matches the repo's own CHANGELOG.md exactly",
    () {
      // assets/CHANGELOG.md exists only because a `..`-escaping asset path
      // silently fails to bundle on a real build (see the comment on this
      // asset in pubspec.yaml) — it is a committed copy, not a symlink, so
      // nothing enforces it stays current except this test. Run from
      // apps/client, hence the two levels up to the repo root.
      final root = File(
        p.join(Directory.current.path, '..', '..', 'CHANGELOG.md'),
      );
      final bundled = File(
        p.join(Directory.current.path, 'assets', 'CHANGELOG.md'),
      );

      expect(
        bundled.readAsStringSync(),
        root.readAsStringSync(),
        reason:
            'apps/client/assets/CHANGELOG.md has drifted from the root '
            'CHANGELOG.md — copy the root file over it again.',
      );
    },
  );

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

      // A real, specific bullet from the file's newest released section —
      // proves the asset actually loaded and parsed, not just that the panel
      // rendered without crashing.
      //
      // The heading is the released version, not "Latest changes": once a
      // release is cut, "## Unreleased" is left empty at the top of the file
      // for the next cycle, and a section with no bullets is dropped by
      // parseChangelogSections rather than rendered as an empty heading.
      expect(find.text('Version v0.6.0'), findsOneWidget);
      expect(find.text('Latest changes'), findsNothing);
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
