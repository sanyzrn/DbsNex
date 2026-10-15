import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_client/widgets/assistant_settings.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/nex_harness.dart';

void main() {
  for (final dark in [false, true]) {
    for (final contrast in [false, true]) {
      testWidgets(
        'assistant and its settings share glass, dark=$dark contrast=$contrast',
        (tester) async {
          final harness = await NexTestHarness.create(name: 'nex_chat_glass_');
          addTearDown(harness.dispose);
          final history = ChatHistory(await SharedPreferences.getInstance());
          addTearDown(history.dispose);
          tester.view.physicalSize = const Size(400, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final locale = Locale(dark ? 'fa' : 'en');
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: dark
                  ? nexDarkTheme(liquidGlass: true)
                  : nexLightTheme(liquidGlass: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(highContrast: contrast, disableAnimations: true),
                child: child!,
              ),
              home: NexAppBackground(
                pattern: NexBackgroundPattern.aurora,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        onPressed: () => AiChatSheet.show(
                          context,
                          preferences: harness.preferences,
                          services: harness.services,
                          history: history,
                          resume: ChatThread(
                            id: 'qa',
                            updatedAt: DateTime(2026),
                            messages: const [
                              ChatMessage(
                                role: ChatRole.user,
                                content: 'سلام\nHello',
                              ),
                              ChatMessage(
                                role: ChatRole.assistant,
                                content: '**Answer**\nمتن پاسخ',
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('chat-composer-surface')),
            findsOneWidget,
          );
          expect(
            find.byType(BackdropFilter),
            contrast ? findsNothing : findsNWidgets(2),
          );
          final l10n = lookupAppLocalizations(locale);
          await tester.tap(find.byTooltip(l10n.assistant));
          await tester.pumpAndSettle();
          expect(find.byType(AssistantSettingsBody), findsOneWidget);
          expect(
            find.byType(BackdropFilter),
            contrast ? findsNothing : findsWidgets,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
