import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/tag_color_picker.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The picker is a disc, a slider, a hex field and two rows of swatches, and
/// every one of them is a way of naming the same colour — so the thing worth
/// testing is that they agree with each other.
void main() {
  /// A phone-shaped surface with room for the whole sheet.
  ///
  /// The default 800x600 is wider than it is tall, and the picker is a 240
  /// disc with four rows under it — on that surface Save starts off screen
  /// and cannot be tapped.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
      MaterialApp(
        theme: nexLightTheme(),
        locale: direction == TextDirection.rtl
            ? const Locale('fa')
            : const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Directionality(
          textDirection: direction,
          child: Scaffold(body: child),
        ),
      );

  Future<void> pump(WidgetTester tester, TextDirection direction) {
    tall(tester);
    return tester.pumpWidget(
      host(
        const TagColorPicker(initial: '#5B9BF0'),
        direction: direction,
      ),
    );
  }

  /// The gradients painted behind the slider tracks.
  List<LinearGradient> gradients(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .toList();

  testWidgets('the slider gradient follows the reading direction', (
    tester,
  ) async {
    // `Slider` is directional — in RTL its zero end is on the right — but a
    // LinearGradient with the default begin/end always paints left to right.
    // In Persian the track therefore ran backwards under its own thumb, so
    // dragging toward black gave white.
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

  group('the wheel', () {
    testWidgets('a tap on the disc changes the colour under it', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        host(const TagColorPicker(initial: '#5B9BF0')),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#5B9BF0');

      // Top of the disc is red, by construction: the sweep starts at -90°.
      final wheel = find.byType(NexColorWheel);
      final box = tester.getRect(wheel);
      await tester.tapAt(Offset(box.center.dx, box.top + 6));
      await tester.pumpAndSettle();

      expect(field.controller!.text, isNot('#5B9BF0'));
      final picked = nexParseTagColor(field.controller!.text)!;
      expect(picked.r, greaterThan(picked.b), reason: 'the top is red');
      expect(picked.r, greaterThan(picked.g), reason: 'the top is red');
    });

    testWidgets('a hex typed in reaches the wheel', (tester) async {
      // The reason the field is editable at all: a colour that has to match
      // something outside Nex is known by its digits, not by its angle.
      tall(tester);
      await tester.pumpWidget(
        host(const TagColorPicker(initial: '#5B9BF0')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '#FF0000');
      await tester.pumpAndSettle();

      expect(tester.widget<NexColorWheel>(find.byType(NexColorWheel)).hue, 0);
    });

    testWidgets('a half-typed hex changes nothing', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        host(const TagColorPicker(initial: '#5B9BF0')),
      );
      await tester.pumpAndSettle();
      final before = tester
          .widget<NexColorWheel>(find.byType(NexColorWheel))
          .hue;

      await tester.enterText(find.byType(TextField), '#FF0');
      await tester.pumpAndSettle();

      expect(
        tester.widget<NexColorWheel>(find.byType(NexColorWheel)).hue,
        before,
      );
    });
  });

  group('the escape-hatch swatch', () {
    testWidgets('a tag can have no colour at all', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        host(const TagColorPicker(initial: '#5B9BF0')),
      );
      await tester.pumpAndSettle();

      final swatches = find.byType(NexColorSwatch);
      expect(
        tester.widget<NexColorSwatch>(swatches.first).icon,
        Icons.block,
        reason: 'a colourless tag has nothing to paint, so it says so',
      );
      expect(tester.widget<NexColorSwatch>(swatches.first).color, isNull);
    });

    testWidgets('an accent always has one, so it shows the default', (
      tester,
    ) async {
      // The bug this is here for: the accent picker offered "No color" for
      // what is actually "back to the shipped blue", drawn as an empty
      // crossed-out dot.
      tall(tester);
      await tester.pumpWidget(
        host(
          const TagColorPicker(
            initial: '#5B9BF0',
            defaultColor: NexColors.accentLight,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.widget<NexColorSwatch>(
        find.byType(NexColorSwatch).first,
      );
      expect(first.icon, isNull);
      expect(first.color, NexColors.accentLight);
    });
  });

  group('recently used', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('nothing is offered before anything has been picked', (
      tester,
    ) async {
      tall(tester);
      final preferences = await NexPreferences.load();
      await tester.pumpWidget(
        host(TagColorPicker(initial: '#5B9BF0', preferences: preferences)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recently used'), findsNothing);
    });

    testWidgets('saving remembers the colour for the next tag', (
      tester,
    ) async {
      // Opened the way the app opens it, so Save actually has a route to
      // resolve and the returned record is the one the caller would get.
      tall(tester);
      final preferences = await NexPreferences.load();
      ({String? color})? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await TagColorPicker.show(
                context,
                initial: '#123456',
                preferences: preferences,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(result?.color, '#123456');
      expect(preferences.recentColors, ['#123456']);
    });

    testWidgets('a remembered colour is offered, and the shipped ones are '
        'not offered twice', (tester) async {
      tall(tester);
      final preferences = await NexPreferences.load();
      await preferences.rememberColor(tagAccentPalette.first);
      await preferences.rememberColor('#123456');

      await tester.pumpWidget(
        host(TagColorPicker(initial: '#5B9BF0', preferences: preferences)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recently used'), findsOneWidget);
      final swatches = tester
          .widgetList<NexColorSwatch>(find.byType(NexColorSwatch))
          .toList();
      // The escape hatch, the five shipped ones, and exactly one recent.
      expect(swatches.length, tagAccentPalette.length + 2);
      expect(
        swatches.last.color,
        nexParseTagColor('#123456'),
      );
    });
  });
}
