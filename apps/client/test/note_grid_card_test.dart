import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/theme_presets.dart';
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

  // The wash is the kind's colour over the card; every word on a tile has to
  // read on its strongest corner, in every appearance and palette.
  test('a tile\'s words read on its wash in every theme', () {
    final bad = <String>[];
    for (final preset in nexThemePresets) {
      for (final base in [
        nexSoftLightTheme(),
        nexSoftDarkTheme(),
        nexOledNightTheme(),
      ]) {
        final scheme = nexApplyThemePreset(base, preset.id, null).colorScheme;
        for (final type in NoteType.values) {
          final tint = nexNoteTypeTint(type.wireName, scheme);
          final dark = scheme.brightness == Brightness.dark;
          for (final alpha in [dark ? 0.09 : 0.07, 0.24]) {
            final wash = Color.alphaBlend(
              tint.withValues(alpha: alpha),
              scheme.surfaceContainerLowest,
            );
            for (final (name, ink) in [
              ('title', scheme.onSurface),
              ('words', nexReadableOn(scheme.onSurfaceVariant, wash)),
              (
                'reminder',
                nexReadableOn(
                  scheme.primary,
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.12),
                    wash,
                  ),
                ),
              ),
              ('kind', nexReadableOn(tint, wash)),
            ]) {
              final ratio = nexContrastRatio(ink, wash);
              if (ratio < 4.5) {
                bad.add(
                  '${preset.id} ${scheme.brightness.name} '
                  '${type.name} $name $alpha: ${ratio.toStringAsFixed(2)}',
                );
              }
            }
          }
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
