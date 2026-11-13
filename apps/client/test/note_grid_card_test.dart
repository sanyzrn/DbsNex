import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// A grid tile keeps one height in its row at any text size: the words give
/// way rather than overflow (2.6.27).
void main() {
  for (final scale in [1.0, 1.3, 1.6, 2.0, 2.6, 3.2]) {
    testWidgets('a grid tile fits at text scale $scale', (tester) async {
      final note = Note(
        id: 'n',
        type: NoteType.text,
        content: 'A long title that goes on and on for a while\nAnd a body that also goes on for quite a few words to fill two lines',
        isUrgent: true,
        dueAt: DateTime(2030),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        deviceId: 'd',
        rev: 1,
        syncState: SyncState.pending,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 164,
                  height: NexNoteGridCard.heightFor(context),
                  child: NexNoteGridCard(
                    note: note,
                    strings: NexCardStrings.fallback,
                    onTap: () {},
                    onLeadingTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
