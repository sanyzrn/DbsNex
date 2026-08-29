import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/search_field_header.dart';
import 'package:nex_ui/nex_ui.dart';

/// The search field sits inside a pill that is already a bordered surface, so
/// the only correct decoration for the field itself is none at all.
///
/// These read the decoration off the [InputDecorator] rather than off the
/// [TextField], because that is the one the theme's defaults have already been
/// merged into — and the merge is the whole bug. `border: InputBorder.none`
/// was passed and a frame was drawn anyway: `border` is only the fallback for
/// `enabledBorder` and `focusedBorder`, and this theme supplies both, so the
/// inner box showed at rest *and* under the caret, in two different colours.
void main() {
  Future<InputDecoration> effective(
    WidgetTester tester, {
    required ThemeData theme,
    required bool searching,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                delegate: SearchFieldHeader(
                  controller: TextEditingController(),
                  focusNode: FocusNode(),
                  searching: searching,
                  onTap: () {},
                  onChanged: (_) {},
                  onClear: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
  }

  for (final (name, theme) in <(String, ThemeData)>[
    ('light', nexLightTheme()),
    ('dark', nexDarkTheme()),
  ]) {
    // Both, because the two frames were different theme entries in different
    // colours — fixing one would have left the other showing.
    for (final searching in [false, true]) {
      final state = searching ? 'ready to type' : 'at rest';
      testWidgets('the search field draws no box of its own, $state ($name)', (
        tester,
      ) async {
        final decoration = await effective(
          tester,
          theme: theme,
          searching: searching,
        );
        expect(decoration.border, InputBorder.none);
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
        expect(decoration.disabledBorder, InputBorder.none);
        expect(decoration.errorBorder, InputBorder.none);
        expect(decoration.focusedErrorBorder, InputBorder.none);
        // The pill is the surface; a fill here would be a second one.
        expect(decoration.filled, isFalse);
      });
    }
  }

  testWidgets('the header lays no band of colour across the background', (
    tester,
  ) async {
    // The tag row below is pinned and does need a backing; this header is not
    // and does not. Painted anyway it was an opaque strip drawn straight
    // across whatever background the reader had chosen.
    final theme = nexDarkTheme();
    await effective(tester, theme: theme, searching: false);
    // Scoped to this header's own subtree, so a ColoredBox belonging to the
    // scaffold or the viewport cannot fail it for the wrong reason.
    final bands = tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is TapRegion && widget.groupId == nexSearchTapGroup,
            ),
            matching: find.byType(ColoredBox),
          ),
        )
        .where((box) => box.color == theme.colorScheme.surface);
    expect(bands, isEmpty);
  });

  testWidgets('and the theme it sits in really does frame a plain field', (
    tester,
  ) async {
    // Guards the test above from passing for the wrong reason. If the theme
    // ever stops bordering fields, these assertions stop meaning anything and
    // should be removed along with the overrides they justify.
    final theme = nexLightTheme();
    expect(theme.inputDecorationTheme.enabledBorder, isNotNull);
    expect(theme.inputDecorationTheme.focusedBorder, isNotNull);
    expect(theme.inputDecorationTheme.filled, isTrue);
  });
}
