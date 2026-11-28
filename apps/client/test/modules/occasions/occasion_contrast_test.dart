import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/occasions/occasion_model.dart';
import 'package:nex_client/modules/occasions/occasion_visuals.dart';

/// White words sit on the kind's colours — the hero card, the calendar
/// tile's month band, the «today» pill — so the colours a kind is drawn in
/// have to carry white at the contrast the words need. The undimmed colours
/// do not (a birthday runs to #FFB347, on which white measures 1.8:1); this
/// pins the deepening that fixes it, at both ends of every gradient, so a
/// future palette change that misses the floor fails the build instead of
/// quietly regressing.
void main() {
  group('white on a kind\'s deepened colours', () {
    for (final kind in OccasionKind.values) {
      final look = OccasionLook.of(kind);
      test('${kind.name}: every end of the gradient carries white', () {
        for (final colour in look.gradient.colors) {
          expect(
            nexContrastRatio(Colors.white, colour),
            greaterThanOrEqualTo(4.5),
            reason: '$kind white on #${colour.toARGB32().toRadixString(16)}',
          );
        }
      });
    }
  });

  group('the undimmed colours do not — the reason the scrim exists', () {
    test('the brightest raw ends sit under 4.5:1', () {
      final birthday = OccasionLook.of(OccasionKind.birthday);
      final other = OccasionLook.of(OccasionKind.other);
      expect(nexContrastRatio(Colors.white, birthday.to), lessThan(4.5));
      expect(nexContrastRatio(Colors.white, other.to), lessThan(4.5));
    });
  });

  group('the scrim itself', () {
    test('is one shared constant, and deepening keeps the hue', () {
      expect(occasionColourScrim, greaterThan(0.3));
      expect(occasionColourScrim, lessThan(0.55));
      final raw = OccasionLook.of(OccasionKind.birthday).from;
      final deep = occasionDeepen(raw);
      // The deepened colour is a darker step toward black of the same hue,
      // not a different colour: channels move together.
      expect(
        HSLColor.fromColor(deep).hue,
        closeTo(HSLColor.fromColor(raw).hue, 0.5),
      );
      expect(
        HSLColor.fromColor(deep).lightness,
        lessThan(HSLColor.fromColor(raw).lightness),
      );
    });
  });
}
