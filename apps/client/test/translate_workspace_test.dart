import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/translate_sheet.dart';

import 'support/nex_harness.dart';

void main() {
  testWidgets(
    'a failed language switch cannot retain the old-language result',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      var calls = 0;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async {
          if (++calls > 1) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Previous language result'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TranslateSheet(
                text: 'Source',
                preferences: h.preferences,
                services: h.services,
                embedded: true,
                adapter: adapter,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Previous language result'), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TranslateSheet)),
      );
      await tester.tap(find.text(l10n.aiOutputLanguageEnglish));
      await tester.pumpAndSettle();
      expect(find.text('Previous language result'), findsNothing);
      expect(find.text(l10n.translateFailed), findsOneWidget);
      expect(find.text(l10n.translateSaveAsNote), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets('$locale inline translation keeps its host and source intact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final copied = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final original = (await h.services.captureText('Original source'))!;
      var requests = 0;
      String? accepted;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': requests == 1
                        ? 'ترجمهٔ فارسی'
                        : 'English translation',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TranslateSheet(
                text: original.content!,
                preferences: h.preferences,
                services: h.services,
                adapter: adapter,
                embedded: true,
                onAddToCaption: (text) => accepted = text,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TranslateSheet)),
      );
      expect(requests, 1);
      await tester.ensureVisible(find.text(l10n.copy));
      await tester.tap(find.text(l10n.copy));
      await tester.pumpAndSettle();
      expect(copied, ['ترجمهٔ فارسی']);
      await tester.tap(find.text(l10n.aiAddToCaption));
      expect(accepted, 'ترجمهٔ فارسی');
      await tester.tap(find.text(l10n.translateSaveAsNote));
      await tester.pumpAndSettle();
      expect(find.byType(TranslateSheet), findsOneWidget);
      expect(
        (await h.services.timeline()).map((n) => n.content),
        contains('ترجمهٔ فارسی'),
      );
      expect(
        (await h.services.getById(original.id))!.content,
        'Original source',
      );
      // Let the saved-note notice leave before tapping the language beneath it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.aiOutputLanguageEnglish));
      await tester.tap(find.text(l10n.aiOutputLanguageEnglish));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.ensureVisible(find.text(l10n.aiAddToCaption));
      await tester.tap(find.text(l10n.aiAddToCaption));
      expect(accepted, 'English translation');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
