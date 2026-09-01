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
          // The panel no longer scrolls inside itself — About is already a
          // scrolling page, and this stands in for that.
          home: Scaffold(
            body: SingleChildScrollView(child: ChangelogPanel()),
          ),
        ),
      );
      // `rootBundle.loadString` is real file IO — it does not reliably resolve
      // inside `pumpAndSettle`'s fake-async pumping alone.
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      // The newest section the file actually has, read from the file rather
      // than written down here. This used to assert `v0.9.1` by name, which
      // was fine until the panel stopped showing every release ever made:
      // a hard-coded version is a test that expires.
      final sections = parseChangelogSections(
        File(
          p.join(Directory.current.path, 'assets', 'CHANGELOG.md'),
        ).readAsStringSync(),
      );
      expect(sections, isNotEmpty);
      final newest = sections.first.heading;
      expect(
        find.text(
          newest == 'Unreleased' ? 'Latest changes' : 'Version $newest',
        ),
        findsOneWidget,
      );

      // And no more than the cap, which is the point of the cap. Counted
      // rather than matched: flutter_test has findsNWidgets and
      // findsAtLeastNWidgets, but no "at most".
      expect(
        tester.widgetList(find.textContaining('Version v')).length,
        lessThanOrEqualTo(10),
      );
    },
  );

  test('parseChangelogSections keeps the newest sections when capped', () {
    // Forty releases in, About should not be an archive with a scrollbar —
    // and the file still holds all of them, so raising the cap loses nothing.
    final raw = [
      for (var i = 40; i >= 1; i--) '## v0.$i.0\n\n- something changed\n',
    ].join('\n');

    expect(parseChangelogSections(raw), hasLength(40));

    final capped = parseChangelogSections(raw, limit: 10);
    expect(capped, hasLength(10));
    expect(capped.first.heading, 'v0.40.0');
    expect(capped.last.heading, 'v0.31.0');
  });

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
