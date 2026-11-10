import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/nex_harness.dart';

/// The short toolbar carries the note's own primary action: a link's Open, a
/// text's Edit. It used to pick its actions by comparing translated labels
/// and icon codes, so anything it did not literally name — a link's Open
/// being the whole point — fell into the More sheet.
void main() {
  Future<void> show(
    WidgetTester tester,
    NexTestHarness h,
    String id, {
    Size size = const Size(900, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: h.services,
            preferences: h.preferences,
            noteId: id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("a link's Open is the toolbar's own first action", (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final note = (await h.services.captureLink('https://example.com/recipe'))!;
    await show(tester, h, note.id);
    final l = AppLocalizations.of(tester.element(find.byType(NoteDetailSheet)));

    // Built on the sheet itself, before More is ever opened — the old code
    // only ever put it behind More, where it did not exist in the tree.
    expect(find.text(l.openLink), findsOneWidget);
    expect(find.text(l.openLink).hitTestable(), findsOneWidget);
    // The link's Open is before Copy, including on platforms without Share.
    expect(
      tester.getTopLeft(find.text(l.openLink)).dx,
      lessThan(tester.getTopLeft(find.text(l.copy)).dx),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a text's Edit stays the toolbar's first action", (tester) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final note = (await h.services.captureText('just words'))!;
    await show(tester, h, note.id);
    final l = AppLocalizations.of(tester.element(find.byType(NoteDetailSheet)));

    expect(find.text(l.edit), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(l.edit)).dx,
      lessThan(tester.getTopLeft(find.text(l.copy)).dx),
    );
    // Copy keeps its slot too: three actions plus More.
    expect(find.text(l.copy), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the More sheet keeps the secondaries, without the primary', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final note = (await h.services.captureLink('https://example.com/recipe'))!;
    await show(tester, h, note.id);
    final l = AppLocalizations.of(tester.element(find.byType(NoteDetailSheet)));

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    // A modal bottom sheet keeps the toolbar mounted underneath it. Check
    // the menu itself for duplicates, rather than assuming the toolbar is
    // offstage while the non-opaque modal route is open.
    final moreSheet = find.byType(BottomSheet);
    expect(moreSheet, findsOneWidget);
    Finder inMore(String label) =>
        find.descendant(of: moreSheet, matching: find.text(label));
    expect(inMore(l.openLink), findsNothing);
    expect(find.text(l.openLink, skipOffstage: false), findsOneWidget);
    expect(inMore(l.details), findsOneWidget);
    expect(inMore(l.delete), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
