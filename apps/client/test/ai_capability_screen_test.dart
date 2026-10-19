import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/screens/ai_provider_screen.dart';
import 'package:nex_client/screens/intelligence_screen.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/nex_harness.dart';

/// 2.1.8: Test connection also finds out what the model can do, the card
/// says so row by row, and the Intelligence page explains a greyed ability
/// in the terms of the provider and model actually chosen.
void main() {
  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
  http.Response gemini(String text) => json({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
        'finishReason': 'STOP',
      },
    ],
  });
  http.Response openAi(String text) => json({
    'choices': [
      {
        'message': {'content': text},
        'finish_reason': 'stop',
      },
    ],
  });

  Future<AppLocalizations> pumpProvider(
    WidgetTester tester,
    NexPreferences preferences, {
    required http.Client client,
    String lang = 'en',
  }) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        theme: lang == 'fa' ? nexDarkTheme() : nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiProviderScreen(preferences: preferences, client: client),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(AiProviderScreen)));
  }

  group('provider screen', () {
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await NexPreferences.load();
    });

    for (final lang in ['en', 'fa']) {
      testWidgets('$lang: Test finds what Gemini can do and keeps it', (
        tester,
      ) async {
        await preferences.setAiProvider(
          const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
        );
        final l10n = await pumpProvider(
          tester,
          preferences,
          lang: lang,
          client: MockClient((request) async {
            final body = request.body;
            if (request.url.path.endsWith(':embedContent')) {
              return json({
                'embedding': {
                  'values': [0.1, 0.2],
                },
              });
            }
            if (body.contains('"file_uri"')) return gemini('Elephants');
            if (body.contains('"audio/wav"')) {
              return json({
                'error': {'message': 'Audio input is not enabled.'},
              }, 400);
            }
            if (body.contains('"image/png"')) return gemini('47');
            return gemini('ok');
          }),
        );
        expect(find.text(l10n.aiCanDoUnchecked), findsOneWidget);
        // The dropdowns that asked the person are gone.
        expect(
          find.byType(DropdownButtonFormField<AiCapabilityMode>),
          findsNothing,
        );

        await tester.tap(find.text(l10n.testConnection));
        await tester.pumpAndSettle();

        final stored = preferences.aiProvider;
        expect(stored.images, AiCapabilityMode.enabled);
        expect(stored.audio, AiCapabilityMode.disabled);
        expect(stored.embeddings, AiCapabilityMode.enabled);
        expect(stored.video, AiCapabilityMode.enabled);
        expect(stored.checkedTime, isNotNull);

        String line(String capability) => tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(ValueKey('ai-capability-$capability')),
                    matching: find.byType(Text),
                  )
                  .last,
            )
            .data!;
        expect(line('images'), l10n.aiCanWorks);
        expect(
          line('audio'),
          '${l10n.aiCanRefusedAudio('gemini-flash-latest')} '
          '(${lang == 'fa' ? '۴۰۰' : '400'})',
        );
        expect(line('embeddings'), l10n.aiCanWorksWith('gemini-embedding-001'));
        expect(line('video'), l10n.aiCanWorks);
        expect(find.byKey(const ValueKey('ai-check-again')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('search found on a router already in use waits to be '
        'turned on', (tester) async {
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openrouter, apiKey: 'k'),
      );
      await preferences.setAiCapabilities(
        const AiCapabilities(
          summarization: true,
          semanticSearch: true,
          relatedNotes: true,
        ),
      );
      expect(preferences.aiProvider.supportsEmbeddings, isFalse);
      final l10n = await pumpProvider(
        tester,
        preferences,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/audio/transcriptions')) {
            return json({
              'error': {'message': 'Not found'},
            }, 404);
          }
          if (request.url.path.endsWith('/embeddings')) {
            return json({
              'data': [
                {
                  'embedding': [0.5, 0.5],
                },
              ],
            });
          }
          return openAi(request.body.contains('image_url') ? '47' : 'ok');
        }),
      );
      await tester.tap(find.text(l10n.testConnection));
      await tester.pumpAndSettle();

      expect(preferences.aiProvider.supportsEmbeddings, isTrue);
      // It would index every note already written: the person decides.
      expect(preferences.aiCapabilities.semanticSearch, isFalse);
      expect(preferences.aiCapabilities.relatedNotes, isFalse);
      expect(preferences.aiCapabilities.summarization, isTrue);
      expect(find.text(l10n.aiSearchHeld), findsOneWidget);
    });

    testWidgets('a check that lands after another provider was chosen does '
        'not bring the old one back', (tester) async {
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'first'),
      );
      final picture = Completer<http.Response>();
      final l10n = await pumpProvider(
        tester,
        preferences,
        client: MockClient((request) async {
          if (request.body.contains('image_url')) return picture.future;
          if (request.url.path.endsWith('/embeddings')) {
            return json({
              'data': [
                {
                  'embedding': [1.0],
                },
              ],
            });
          }
          if (request.url.path.endsWith('/audio/transcriptions')) {
            return json({'text': ''});
          }
          return openAi('ok');
        }),
      );
      await tester.tap(find.text(l10n.testConnection));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(l10n.aiCanDoChecking), findsOneWidget);

      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'g'),
      );
      picture.complete(openAi('47'));
      await tester.pumpAndSettle();

      expect(preferences.aiProvider.provider, AiProvider.gemini);
      final openai = preferences.configFor(AiProvider.openai);
      expect(openai.checkedTime, isNotNull);
      expect(openai.images, AiCapabilityMode.enabled);
      expect(openai.apiKey, 'first');
    });

    testWidgets('a Gemini bought from a reseller is reached at its own '
        'address, in Gemini\'s format', (tester) async {
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'first'),
      );
      final hosts = <String>{};
      final l10n = await pumpProvider(
        tester,
        preferences,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          final body = request.body;
          if (request.url.path.endsWith(':embedContent')) {
            return json({
              'embedding': {
                'values': [0.1],
              },
            });
          }
          if (body.contains('"file_uri"')) return gemini('Elephants');
          return gemini(body.contains('"image/png"') ? '47' : 'ok');
        }),
      );
      // Only Gemini takes an optional address.
      expect(find.byKey(const ValueKey('ai-gemini-address')), findsNothing);
      await tester.tap(find.text(AiProvider.gemini.label));
      await tester.pumpAndSettle();
      final address = find.byKey(const ValueKey('ai-gemini-address'));
      expect(address, findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, l10n.apiKey),
        'reseller-key',
      );

      // A key is never offered to a plain-http address on the internet.
      await tester.enterText(address, 'http://gw.example/v1beta');
      await tester.pump();
      expect(find.text(l10n.aiGatewayInvalid), findsOneWidget);
      // `FilledButton.icon` is a subclass, which a type finder misses.
      final test = find.ancestor(
        of: find.text(l10n.testConnection),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(test).onPressed, isNull);

      await tester.enterText(address, 'https://gw.example/v1beta');
      await tester.pump();
      expect(find.text(l10n.aiGatewayInvalid), findsNothing);
      await tester.tap(test);
      await tester.pumpAndSettle();

      expect(hosts, {'gw.example'});
      final saved = preferences.aiProvider;
      expect(saved.provider, AiProvider.gemini);
      expect(saved.baseUrl, 'https://gw.example/v1beta');
      expect(saved.gatewayHost, 'gw.example');
      expect(CloudAIAdapter.watchesYouTube(saved), isTrue);

      // Switching away does not carry the address to a provider that has
      // only one host.
      await tester.tap(find.text(AiProvider.openai.label));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-gemini-address')), findsNothing);
    });

    testWidgets('a model is picked from the provider\'s own list', (
      tester,
    ) async {
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
      );
      final l10n = await pumpProvider(
        tester,
        preferences,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return json({
            'models': [
              for (final id in [
                'gemini-flash-latest',
                'gemini-2.5-pro',
                'gemini-2.5-flash-lite',
              ])
                {
                  'name': 'models/$id',
                  'supportedGenerationMethods': ['generateContent'],
                },
            ],
          });
        }),
      );
      expect(find.text(l10n.aiModelDefault('gemini-flash-latest')), findsOne);
      await tester.tap(find.byKey(const ValueKey('ai-model-browse')));
      await tester.pumpAndSettle();
      expect(find.text('gemini-2.5-pro'), findsOneWidget);
      expect(find.text(l10n.aiModelBrowseDefault), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('ai-model-search')),
        'flash',
      );
      await tester.pump();
      expect(find.text('gemini-2.5-pro'), findsNothing);
      await tester.tap(find.text('gemini-2.5-flash-lite'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, l10n.model),
      );
      expect(field.controller!.text, 'gemini-2.5-flash-lite');
      // Picked, not yet tested: nothing is stored until Test passes.
      expect(preferences.aiProvider.model, isEmpty);
    });
  });

  group('Intelligence page', () {
    late NexTestHarness h;

    setUp(() async => h = await NexTestHarness.create(name: 'nex_intel_'));
    tearDown(() => h.dispose());

    testWidgets('fa: counts what can work and says why the rest cannot', (
      tester,
    ) async {
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.anthropic, apiKey: 'k'),
      );
      await h.preferences.setAiCapabilities(
        const AiCapabilities(
          transcription: true,
          ocr: true,
          summarization: true,
          tagSuggestions: true,
          semanticSearch: true,
          relatedNotes: true,
        ),
      );
      tester.view.physicalSize = const Size(412, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: IntelligenceScreen(
            services: h.services,
            preferences: h.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(IntelligenceScreen)),
      );
      expect(find.text(l10n.intelligenceAbilities), findsOneWidget);
      // Photo reading, summaries and tags; speech and search have nothing
      // behind them at Anthropic, and the paused ability is not counted.
      final total = nexRelatedNotesAvailable ? 6 : 5;
      expect(
        find.text(
          l10n.intelligenceAbilitiesOn('۳', nexDigits('$total', persian: true)),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.aiCanAbsentAudio('Anthropic')), findsOneWidget);
      expect(find.text(l10n.aiCanAbsentSearch('Anthropic')), findsWidgets);
      expect(find.text(l10n.intelligenceUnchecked), findsOneWidget);
      expect(find.text(l10n.intelligenceStateOn('Anthropic')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
