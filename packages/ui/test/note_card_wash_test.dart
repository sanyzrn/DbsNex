import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// The list card sits on the same wash of its kind's colour as a grid tile
/// (2.6.30): one look in both layouts, the kind seen at a glance.
void main() {
  Note note(NoteType type) => Note(
    id: 'n-${type.name}',
    type: type,
    content: 'the boiler',
    createdAt: DateTime.utc(2026, 11, 1),
    updatedAt: DateTime.utc(2026, 11, 1),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  LinearGradient gradientOf(WidgetTester tester) {
    final ink = tester.widget<Ink>(
      find.descendant(of: find.byType(NoteCard), matching: find.byType(Ink)),
    );
    return (ink.decoration! as BoxDecoration).gradient! as LinearGradient;
  }

  for (final theme in [nexLightTheme(), nexSoftDarkTheme()]) {
    final scheme = theme.colorScheme;
    for (final picked in <bool?>[null, true]) {
      testWidgets(
        '${scheme.brightness.name}, picked $picked: each kind its own wash',
        (tester) async {
          final starts = <Color>{};
          for (final type in [NoteType.text, NoteType.voice, NoteType.link]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SizedBox(
                    width: 400,
                    child: NoteCard(note: note(type), selected: picked),
                  ),
                ),
              ),
            );
            final wash = nexNoteWash(
              type.wireName,
              scheme,
              picked: picked ?? false,
            );
            expect(gradientOf(tester).colors, [wash.from, wash.to]);
            starts.add(wash.from);
            // The quiet words stay readable on the tint.
            expect(
              nexContrast(wash.muted, wash.from),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(starts, hasLength(3), reason: 'the kinds are told apart');
        },
      );
    }
  }

  test('a picked card is clearly stronger than an ordinary one', () {
    final scheme = nexLightTheme().colorScheme;
    final plain = nexNoteWash('text', scheme);
    final picked = nexNoteWash('text', scheme, picked: true);
    final ground = scheme.surfaceContainerLowest;
    expect(
      nexContrast(picked.from, ground),
      greaterThan(nexContrast(plain.from, ground)),
    );
  });
}
