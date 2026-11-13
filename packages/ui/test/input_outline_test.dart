import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Every text field takes its outline from the theme, in every state and
/// every appearance — including disabled, which used to fall back to
/// Material's default 4 px outline wherever a screen asked for "an outline"
/// with `OutlineInputBorder()`.
void main() {
  final themes = <String, ThemeData Function()>{
    'light': nexLightTheme,
    'dark': nexDarkTheme,
    'soft light': nexSoftLightTheme,
    'soft dark': nexSoftDarkTheme,
    'night': nexOledNightTheme,
  };

  for (final MapEntry(key: name, value: build) in themes.entries) {
    test('$name: resting, disabled and focused share the corners', () {
      final input = build().inputDecorationTheme;
      for (final border in [
        input.border,
        input.enabledBorder,
        input.disabledBorder,
        input.focusedBorder,
        input.errorBorder,
      ]) {
        expect(border, isA<OutlineInputBorder>());
        expect(
          (border! as OutlineInputBorder).borderRadius,
          BorderRadius.circular(NexRadius.md),
        );
      }
      // Quieter than a field you can type in, never invisible.
      final disabled = (input.disabledBorder! as OutlineInputBorder).borderSide;
      final enabled = (input.enabledBorder! as OutlineInputBorder).borderSide;
      expect(disabled.color.a, lessThan(1));
      expect(disabled.color.a, greaterThan(0));
      expect(disabled.width, greaterThan(0));
      expect(enabled.style, BorderStyle.solid);
    });

    testWidgets('$name: a disabled field draws the theme outline', (
      tester,
    ) async {
      final theme = build();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Amount'),
            ),
          ),
        ),
      );
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final applied = decorator.decoration.applyDefaults(
        theme.inputDecorationTheme,
      );
      expect(applied.disabledBorder, theme.inputDecorationTheme.disabledBorder);
    });
  }
}
