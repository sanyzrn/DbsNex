import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final preset in nexThemePresets) {
    for (final dark in [false, true]) {
      for (final glass in [false, true]) {
        testWidgets(
          '${preset.id}, dark=$dark, glass=$glass: dialog separates from a matching sheet',
          (tester) async {
            final seed = nexThemePresetSeed(preset.id);
            final base = dark
                ? nexDarkTheme(accentSeed: seed, liquidGlass: glass)
                : nexLightTheme(accentSeed: seed, liquidGlass: glass);
            final theme = nexApplyThemePreset(base, preset.id, seed);
            late ModalRoute<void> route;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  backgroundColor: theme.dialogTheme.backgroundColor,
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => nexShowDialog<void>(
                        context: context,
                        builder: (context) {
                          route = ModalRoute.of<void>(context)!;
                          return NexAlertDialog(
                            title: const Text('Details'),
                            content: const NexDialogBody(child: Text('Photo')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          );
                        },
                      ),
                      child: const Text('Open details'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open details'));
            await tester.pumpAndSettle();
            expect(
              route.barrierColor,
              glass ? Colors.black.withValues(alpha: 0.24) : Colors.black54,
            );
            expect(
              find.byType(BackdropFilter),
              glass ? findsOneWidget : findsNothing,
            );
            final material = tester.widget<Material>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Material && widget.type == MaterialType.card,
                ),
              ),
            );
            final border = material.shape! as RoundedRectangleBorder;
            if (glass) {
              expect(border.side, BorderSide.none);
            } else {
              expect(border.side.style, BorderStyle.solid);
              expect(
                nexContrastRatio(border.side.color, material.color!),
                greaterThanOrEqualTo(3),
                reason: 'The frame must be visible against its own surface.',
              );
            }
            await tester.tap(find.text('Close'));
            await tester.pumpAndSettle();
            expect(find.text('Details'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('standard dialogs respect a theme-provided scrim', (
    tester,
  ) async {
    final base = nexLightTheme();
    late ModalRoute<void> route;
    await tester.pumpWidget(
      MaterialApp(
        theme: base.copyWith(
          dialogTheme: base.dialogTheme.copyWith(barrierColor: Colors.black38),
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => nexShowDialog<void>(
              context: context,
              builder: (context) {
                route = ModalRoute.of<void>(context)!;
                return const NexAlertDialog(title: Text('Details'));
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(route.barrierColor, Colors.black38);
  });

  testWidgets(
    'an open glass sheet gains an opaque backing when glass turns off',
    (tester) async {
      final glass = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: glass,
          builder: (context, enabled, _) => MaterialApp(
            theme: nexLightTheme(liquidGlass: enabled),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => nexShowSheet<void>(
                    context: context,
                    builder: (_) => TextButton(
                      onPressed: () => glass.value = false,
                      child: const Text('Disable glass'),
                    ),
                  ),
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.text('Disable glass'));
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsNothing);
      final surface = tester.widget<NexGlassSurface>(
        find.byType(NexGlassSurface),
      );
      expect(
        surface.fallbackColor,
        nexLightTheme().colorScheme.surfaceContainerLowest,
      );
      final backing = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(NexGlassSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        backing.any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color == surface.fallbackColor,
        ),
        isTrue,
      );
      glass.dispose();
    },
  );
}
