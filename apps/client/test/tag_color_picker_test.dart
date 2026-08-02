import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/tag_color_picker.dart';
import 'package:nex_ui/nex_ui.dart';

/// The colour sliders have to run the same way round as the thumb that moves
/// along them.
void main() {
  Future<void> pump(WidgetTester tester, TextDirection direction) =>
      tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          locale: direction == TextDirection.rtl
              ? const Locale('fa')
              : const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: direction,
            child: const Scaffold(body: TagColorPicker(initial: '#5B9BF0')),
          ),
        ),
      );

  /// The gradients painted behind the sliders, in the order they are built.
  List<LinearGradient> gradients(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .toList();

  testWidgets('the slider gradients follow the reading direction', (
    tester,
  ) async {
    // `Slider` is directional — in RTL its zero end is on the right — but a
    // LinearGradient with the default begin/end always paints left to right.
    // In Persian the track therefore ran backwards under its own thumb, so
    // dragging toward red gave blue.
    for (final direction in TextDirection.values) {
      await pump(tester, direction);
      final painted = gradients(tester);
      expect(painted, isNotEmpty, reason: 'no slider tracks found');
      for (final gradient in painted) {
        expect(
          gradient.begin,
          isA<AlignmentDirectional>(),
          reason: 'a physical alignment cannot follow the layout',
        );
        expect(
          gradient.begin.resolve(direction),
          direction == TextDirection.rtl
              ? Alignment.centerRight
              : Alignment.centerLeft,
        );
      }
    }
  });
}
