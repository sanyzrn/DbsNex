import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
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
