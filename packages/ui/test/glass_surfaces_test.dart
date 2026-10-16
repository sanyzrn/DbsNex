import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final dark in [false, true]) {
    for (final direction in TextDirection.values) {
      for (final mode in ['solid', 'glass', 'contrast']) {
        testWidgets('$mode, dark=$dark, $direction: shared surfaces work', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(360, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final glass = mode != 'solid';
          var chosen = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark
                  ? nexDarkTheme(liquidGlass: glass)
                  : nexLightTheme(liquidGlass: glass),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  highContrast: mode == 'contrast',
                  disableAnimations: true,
                  textScaler: TextScaler.linear(1.8),
                ),
                child: Directionality(textDirection: direction, child: child!),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: const NexAppBar(title: Text('Tools')),
                  body: Padding(
                    padding: const EdgeInsets.all(NexSpacing.md),
                    child: Column(
                      children: [
                        NexSurface(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          child: ListTile(
                            title: const Text('Settings'),
                            trailing: NexPopupMenuButton<int>(
                              icon: const Icon(Icons.more_vert),
                              initialValue: 2,
                              onSelected: (value) => chosen = value,
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 1, child: Text('First')),
                                PopupMenuItem(value: 2, child: Text('Second')),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => NexAlertDialog(
                              title: const Text('Confirm'),
                              content: const Text('Keep this choice?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Done'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('Open dialog'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (glass) {
            expect(
              tester
                  .widget<AppBar>(find.byType(AppBar))
                  .systemOverlayStyle
                  ?.statusBarIconBrightness,
              dark ? Brightness.light : Brightness.dark,
            );
          }
          final blurred = mode == 'glass';
          expect(
            find.byType(BackdropFilter),
            blurred ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          expect(
            find.byType(BackdropFilter),
            blurred ? findsNWidgets(2) : findsNothing,
          );
          await tester.tap(find.text('Second'));
          await tester.pumpAndSettle();
          expect(chosen, 2);
          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('First'), findsNothing);
          await tester.tap(find.text('Open dialog'));
          await tester.pumpAndSettle();
          expect(find.text('Confirm'), findsOneWidget);
          expect(
            find.byType(BackdropFilter),
            blurred ? findsNWidgets(2) : findsNothing,
          );
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.text('Confirm'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
