import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/tag_manager_screen.dart';

import 'support/nex_harness.dart';

/// Merging one tag into another moves every note that carries the source.
/// It used to happen on the tap of the target row — no word, no way back —
/// while deleting a tag in the same screen had always confirmed. It
/// confirms now, naming both tags and the notes that follow them.
void main() {
  testWidgets('merge names its cost, and cancel costs nothing', (tester) async {
    final harness = await NexTestHarness.create(name: 'nex_tag_merge_');
    addTearDown(harness.dispose);

    final note = await harness.services.captureText('carries the source tag');
    await harness.services.addTag(noteId: note.id, name: 'alpha');
    await harness.services.createTag('beta');
    await harness.services.refreshTimeline();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TagManagerScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);

    // alpha's row menu → Merge → the target sheet → beta. The sheet's row
    // is the last 'beta' on screen: the manager's own list is behind the
    // sheet, still built, still findable.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta').last);
    await tester.pumpAndSettle();

    // The confirmation: one note moves, said with both names.
    expect(find.text('Merge tags?'), findsOneWidget);
    expect(find.textContaining('1 note carrying'), findsOneWidget);
    expect(find.textContaining('alpha'), findsWidgets);
    expect(find.textContaining('beta'), findsWidgets);

    // Cancel keeps both tags where they were.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.textContaining('1 note carrying'), findsNothing);
  });

  testWidgets('confirmed, the merge happens and says where the notes went', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_tag_merge2_');
    addTearDown(harness.dispose);

    final note = await harness.services.captureText('carries the source tag');
    await harness.services.addTag(noteId: note.id, name: 'alpha');
    await harness.services.createTag('beta');
    await harness.services.refreshTimeline();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TagManagerScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge').last);
    await tester.pumpAndSettle();

    // alpha is gone — its one note wears beta now — and the banner says the
    // name of the tag that kept the notes.
    expect(find.text('alpha'), findsNothing);
    expect(find.textContaining('Merged into beta'), findsOneWidget);
  });
}
