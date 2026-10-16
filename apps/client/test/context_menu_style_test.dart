import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/widgets/note_context_menu.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final dark in [false, true]) {
    for (final glass in [false, true]) {
      testWidgets(
        'link and card menu share type, glyphs and corners (dark=$dark, glass=$glass)',
        (tester) async {
          final theme = dark
              ? nexDarkTheme(liquidGlass: glass)
              : nexLightTheme(liquidGlass: glass);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Column(
                  children: [
                    NoteContextMenu(
                      entries: [NoteMenuEntry(NexHoldAction.copy, () {})],
                      child: const SizedBox(
                        height: 80,
                        child: Center(child: Text('card')),
                      ),
                    ),
                    Builder(
                      builder: (context) => TextButton(
                        onPressed: () {
                          nexShowContextMenu<String>(
                            context: context,
                            position: const RelativeRect.fromLTRB(
                              60,
                              100,
                              0,
                              0,
                            ),
                            items: [
                              const PopupMenuItem(
                                value: 'open',
                                child: NexMenuEntryContent(
                                  icon: Icons.open_in_new,
                                  label: 'Open link',
                                ),
                              ),
                            ],
                          );
                        },
                        child: const Text('link menu'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.longPress(find.text('card'));
          await tester.pumpAndSettle();
          final cardStyle = tester.widget<Text>(find.text('Copy')).style!;
          final cardIcon = tester.widget<Icon>(
            find.byIcon(Icons.copy_outlined),
          );
          await tester.tapAt(const Offset(750, 400));
          await tester.pumpAndSettle();
          await tester.tap(find.text('link menu'));
          await tester.pumpAndSettle();
          final linkStyle = tester.widget<Text>(find.text('Open link')).style!;
          expect(linkStyle.fontSize, cardStyle.fontSize);
          expect(linkStyle.fontWeight, cardStyle.fontWeight);
          expect(
            tester.widget<Icon>(find.byIcon(Icons.open_in_new)).size,
            cardIcon.size,
          );
          expect(cardIcon.size, 20);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Material &&
                  w.shape is RoundedRectangleBorder &&
                  (w.shape! as RoundedRectangleBorder).borderRadius ==
                      BorderRadius.circular(NexRadius.lg),
            ),
            findsWidgets,
          );
          if (glass) {
            final surface = tester.widget<NexGlassSurface>(
              find.byType(NexGlassSurface),
            );
            expect(surface.material, NexGlassMaterial.floating);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
