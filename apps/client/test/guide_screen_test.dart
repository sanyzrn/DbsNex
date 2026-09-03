import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/guide_screen.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

/// The guide is prose in a bundled file rather than strings in the ARB
/// catalogues, which buys a lot and costs one thing: nothing else checks that
/// the two languages stayed in step. That is what most of this file is for.
void main() {
  Future<void> open(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GuideScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens in English and renders as Markdown, not source', (
    tester,
  ) async {
    await open(tester, const Locale('en'));

    expect(find.text('How Nex works'), findsOneWidget);
    expect(find.byType(NexMarkdown), findsOneWidget);
    // A heading arrives without its hashes, which is the whole reason this
    // goes through the renderer rather than a Text.
    expect(find.textContaining('Reminders'), findsWidgets);
    expect(find.textContaining('## '), findsNothing);
  });

  testWidgets('opens the Persian guide when the app is in Persian', (
    tester,
  ) async {
    await open(tester, const Locale('fa'));

    expect(find.text('نکس چطور کار می‌کند'), findsOneWidget);
    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('یادآورها'), findsWidgets);
    // The English file must not be what a Persian reader gets.
    expect(find.textContaining('Reminders'), findsNothing);
  });

  group('the two languages stay in step', () {
    String read(String name) =>
        File(p.join(Directory.current.path, 'assets', 'guide', name))
            .readAsStringSync();

    List<String> sectionsOf(String source) => [
      for (final line in source.split('\n'))
        if (line.startsWith('## ')) line,
    ];

    test('both files exist and neither is a stub', () {
      for (final name in ['en.md', 'fa.md']) {
        expect(read(name).trim().length, greaterThan(1000), reason: name);
      }
    });

    test('they have the same number of sections', () {
      // Not the same *words* — a translation is not a mapping — but a section
      // that exists in one language and not the other is a reader told less
      // because of the language they read in.
      expect(
        sectionsOf(read('fa.md')).length,
        sectionsOf(read('en.md')).length,
      );
    });

    test('the Persian guide is actually in Persian', () {
      // The failure this catches is the English file copied across as a
      // placeholder and never replaced.
      final persian = RegExp(r'[\u0600-\u06FF]');
      final sections = sectionsOf(read('fa.md'));
      expect(sections, isNotEmpty);
      for (final heading in sections) {
        expect(persian.hasMatch(heading), isTrue, reason: heading);
      }
    });
  });
}
