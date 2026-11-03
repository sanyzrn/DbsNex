import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/screens/disclosures_screen.dart';
import 'package:nex_client/screens/intelligence_screen.dart';
import 'package:nex_client/screens/memory_screen.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_client/widgets/assistant_settings.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

Widget app(Widget body, {String locale = 'en', bool dark = false}) =>
    MaterialApp(
      key: ObjectKey(body),
      locale: Locale(locale),
      theme: dark ? nexDarkTheme() : nexLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: body,
    );

void main() {
  test(
    'legacy text is retained; absent Memory stays off and choices survive reload',
    () async {
      final h = await NexTestHarness.create(
        preferences: {
          'ai.userIntroduction': 'Existing introduction',
          'ai.transcription': false,
          'brief.instruction': 'My brief',
        },
      );
      addTearDown(h.dispose);
      final prefs = h.preferences;
      expect(prefs.aiMemoryEnabled, isFalse);
      expect(prefs.aiMemoryConsentSeen, isFalse);
      await prefs.setAiEnabled(true);
      expect(prefs.aiUserIntroduction, 'Existing introduction');
      expect(prefs.effectiveAiMemory, isEmpty);
      await prefs.setAiMemoryEnabled(true);
      expect(prefs.effectiveAiMemory, 'Existing introduction');
      await prefs.setAiEnabled(false);
      expect(prefs.aiMemoryEnabled, isTrue);
      expect(prefs.effectiveAiMemory, isEmpty);
      await prefs.setAiEnabled(true);
      final loaded = await NexPreferences.load();
      addTearDown(loaded.dispose);
      expect(loaded.aiMemoryEnabled, isTrue);
      expect(loaded.effectiveAiMemory, 'Existing introduction');
      expect(loaded.aiCapabilities.transcription, isFalse);
      expect(loaded.briefInstruction, 'My brief');
      await loaded.setAiMemoryEnabled(false);
      await loaded.setAiEnabled(false);
      await loaded.setAiEnabled(true);
      expect(loaded.aiMemoryEnabled, isFalse);
      expect(loaded.aiUserIntroduction, 'Existing introduction');
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets(
      '$locale Memory asks once, hides the field and preserves its text',
      (tester) async {
        final h = await NexTestHarness.create(
          preferences: {'ai.userIntroduction': 'Existing introduction'},
        );
        addTearDown(h.dispose);
        await h.preferences.setAiEnabled(true);
        await tester.pumpWidget(
          app(
            MemoryScreen(preferences: h.preferences),
            locale: locale,
            dark: locale == 'fa',
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('memory-enabled'));
        expect(find.byType(NexTextField), findsNothing);
        final l10n = AppLocalizations.of(tester.element(toggle));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text(l10n.memoryConsentBody), findsOneWidget);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(h.preferences.aiMemoryEnabled, isFalse);
        expect(h.preferences.aiMemoryConsentSeen, isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.memoryEnable));
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: find.byKey(const ValueKey('memory-introduction')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(field).controller!.text,
          'Existing introduction',
        );
        await tester.enterText(field, 'Updated introduction');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.byType(NexTextField), findsNothing);
        expect(h.preferences.aiUserIntroduction, 'Updated introduction');
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text(l10n.memoryConsentBody), findsNothing);
        expect(
          tester.widget<TextField>(field).controller!.text,
          'Updated introduction',
        );
        await h.preferences.setAiEnabled(false);
        await tester.pumpAndSettle();
        expect(tester.widget<NexSwitchTile>(toggle).onChanged, isNull);
        expect(h.preferences.aiMemoryEnabled, isTrue);
        await h.preferences.setAiEnabled(true);
        await tester.pumpAndSettle();
        expect(tester.widget<NexSwitchTile>(toggle).onChanged, isNotNull);
        await tester.pumpWidget(
          app(
            Scaffold(body: AssistantSettingsBody(preferences: h.preferences)),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.assistantAboutMe), findsNothing);
        expect(h.preferences.aiUserIntroduction, 'Updated introduction');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$locale Intelligence gates its three options; Security keeps disclosures',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        await tester.pumpWidget(
          app(
            SettingsSheet(services: h.services, preferences: h.preferences),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final category = find.byKey(
          const ValueKey('settings-category-intelligence'),
        );
        await tester.ensureVisible(category);
        await tester.pumpAndSettle();
        await tester.tap(category);
        await tester.pumpAndSettle();
        final memory = find.byKey(const ValueKey('intelligence-memory-row'));
        await tester.ensureVisible(memory);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(tester.element(memory));
        ListTile row(String title) => tester.widget<ListTile>(
          find
              .ancestor(
                of: find.text(title).last,
                matching: find.byType(ListTile),
              )
              .first,
        );
        for (final title in [
          l10n.assistant,
          l10n.briefTitle,
          l10n.memoryTitle,
        ]) {
          expect(row(title).enabled, isFalse);
          expect(row(title).onTap, isNull);
        }
        await h.preferences.setAiEnabled(true);
        await tester.pumpAndSettle();
        for (final title in [
          l10n.assistant,
          l10n.briefTitle,
          l10n.memoryTitle,
        ]) {
          expect(row(title).enabled, isTrue);
          expect(row(title).onTap, isNotNull);
        }
        await tester.pumpWidget(
          app(
            IntelligenceScreen(
              services: h.services,
              preferences: h.preferences,
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.disclosuresTitle), findsNothing);
        await tester.pumpWidget(
          app(
            SettingsSheet(services: h.services, preferences: h.preferences),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final security = find.byKey(
          const ValueKey('settings-category-security'),
        );
        await tester.ensureVisible(security);
        await tester.pumpAndSettle();
        await tester.tap(security);
        await tester.pumpAndSettle();
        final log = find.text(l10n.disclosuresTitle);
        await tester.ensureVisible(log);
        await tester.pumpAndSettle();
        await tester.tap(log);
        await tester.pumpAndSettle();
        expect(find.byType(DisclosuresScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an open assistant reads the Memory switch for every request', (
    tester,
  ) async {
    final h = await NexTestHarness.create(
      preferences: {'ai.userIntroduction': 'PRIVATE_MEMORY_CONTEXT'},
    );
    addTearDown(h.dispose);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    );
    final bodies = <String>[];
    final client = MockClient((request) async {
      bodies.add(request.body);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Okay'},
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AiChatSheet(
            services: h.services,
            preferences: h.preferences,
            history: h.preferences.chatHistory,
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AiChatSheet),
      matching: find.byType(TextField),
    );
    for (final on in [false, true, false]) {
      await h.preferences.setAiMemoryEnabled(on);
      await tester.enterText(field, on ? 'With context' : 'Without context');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('send')));
      await tester.pumpAndSettle();
      expect(bodies.last.contains('PRIVATE_MEMORY_CONTEXT'), on);
    }
    expect(bodies, hasLength(3));
    expect(h.preferences.aiUserIntroduction, 'PRIVATE_MEMORY_CONTEXT');
  });
}
