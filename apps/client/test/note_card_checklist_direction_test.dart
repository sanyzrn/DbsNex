import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Each checklist line follows its own words: in a mixed Persian/English
/// list the checkbox sits at the start of the line it belongs to, not exiled
/// to the far edge of the card.
void main() {
  final written = DateTime.utc(2026, 11, 9);
  Note note(String content) => Note(
    id: 'a',
    type: NoteType.checklist,
    content: content,
    createdAt: written,
    updatedAt: written,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.synced,
  );

  testWidgets("each line's checkbox sits at that line's own start", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 330);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteCard(
            note: note('- [ ] خرید نان\n- [ ] Buy milk'),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only the two checklist lines set an explicit direction; every other row
    // in the card inherits the ambient one.
    expect(
      find.byWidgetPredicate(
        (w) => w is Row && w.textDirection == TextDirection.rtl,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Row && w.textDirection == TextDirection.ltr,
      ),
      findsOneWidget,
    );
  });
}
