import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_hero.dart';
import 'package:nex_client/widgets/nex_shelf.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

/// Contrast guards for the derived/generated colours the 2.6.16 visual audit
/// found escaping the tested floors — the vault's bank-card ink (V-01), the
/// notice capsule's action (V-02), the module hues (V-06) and the NexHue
/// icons (V-06). These assert the *mechanism* the fixes use, so a future
/// palette change that misses its floor fails the build instead of aging
/// quietly.
void main() {
  group('vault bank-card ink (V-01)', () {
    test('whichever ink the estimator picks clears 4.5:1 on the face', () {
      for (final hex in tagAccentPalette) {
        final face = nexParseTagColor(hex)!;
        final white = nexContrastRatio(Colors.white, face);
        final dark = nexContrastRatio(const Color(0xFF14161A), face);
        final chosen = white >= 4.5 ? white : dark;
        expect(
          chosen,
          greaterThanOrEqualTo(4.5),
          reason: 'card number/CVV2 ink on #$hex fell to '
              '${chosen.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('notice capsule action (V-02)', () {
    test('the light theme\'s action token reads on the dark capsule', () {
      final theme = nexSoftLightTheme();
      final action = theme.snackBarTheme.actionTextColor!;
      for (final capsule in const [Color(0xFF17181B), Color(0xFF2C2E33)]) {
        expect(nexContrastRatio(action, capsule), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('module hues (V-06)', () {
    testWidgets('every hue clears 3:1 as a graphic on the light card', (
      tester,
    ) async {
      final ids = const [
        'habits',
        'smoke_free',
        'expenses',
        'gold',
        'words',
        'parking',
        'medicine',
        'warranty',
        'maintenance',
        'price_lens',
        'lent_borrowed',
        'occasions',
      ];
      final accents = <String, Color>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: nexSoftLightTheme(),
          home: Builder(
            builder: (context) {
              for (final id in ids) {
                accents[id] = nexModuleAccent(context, id);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final card = nexSoftLightTheme().colorScheme.surfaceContainerLowest;
      for (final id in ids) {
        expect(
          nexContrastRatio(accents[id]!, card),
          greaterThanOrEqualTo(3),
          reason: '$id icon on the light card (SC 1.4.11)',
        );
      }
    });
  });

  group('NexHue icons on their own wash (V-06)', () {
    test('every light hue clears 3:1 on its 16% wash over the card', () {
      final card = nexSoftLightTheme().colorScheme.surfaceContainerLowest;
      for (final hue in NexHue.values) {
        final icon = hue.light;
        final wash = Color.alphaBlend(icon.withValues(alpha: 0.16), card);
        expect(
          nexContrastRatio(icon, wash),
          greaterThanOrEqualTo(3),
          reason: '${hue.name} icon on its wash',
        );
      }
    });
  });
}
