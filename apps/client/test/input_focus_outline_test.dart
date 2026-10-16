import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  for (final dark in [false, true]) {
    for (final glass in [false, true]) {
      for (final assistant in [false, true]) {
        testWidgets(
          'continuous focused outline: assistant=$assistant dark=$dark glass=$glass',
          (tester) async {
            final h = await NexTestHarness.create();
            addTearDown(h.dispose);
            tester.view.physicalSize = const Size(400, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark
                    ? nexDarkTheme(liquidGlass: glass)
                    : nexLightTheme(liquidGlass: glass),
                locale: Locale(dark ? 'fa' : 'en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: assistant
                    ? Scaffold(
                        body: AiChatSheet(
                          preferences: h.preferences,
                          services: h.services,
                          history: h.preferences.chatHistory,
                        ),
                      )
                    : SettingsSheet(
                        services: h.services,
                        preferences: h.preferences,
                      ),
              ),
            );
            await tester.pumpAndSettle();
            final surface = find.byKey(
              ValueKey(
                assistant ? 'chat-composer-surface' : 'settings-search-surface',
              ),
            );
            final input = find.descendant(
              of: surface,
              matching: find.byType(TextField),
            );
            await tester.tap(input);
            await tester.pumpAndSettle();
            final decorator = tester.widget<InputDecorator>(
              find.descendant(
                of: surface,
                matching: find.byType(InputDecorator),
              ),
            );
            expect(decorator.isFocused, isTrue);
            final decoration = decorator.decoration;
            final radius = tester.widget<NexSurface>(surface).borderRadius;
            // Check the effective theme-merged borders: a plain fallback border
            // used to inherit a smaller radius and get clipped by this surface.
            expect(
              (decoration.enabledBorder as OutlineInputBorder).borderRadius,
              radius,
            );
            expect(
              (decoration.focusedBorder as OutlineInputBorder).borderRadius,
              radius,
            );
            expect(
              decoration.focusedBorder!.borderSide.width,
              nexFocusRingWidth,
            );
            expect(decoration.filled, isFalse);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
