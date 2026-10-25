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

/// 2.3.3: the translation picks its own direction, keeps what came back for
/// the session, and translates a long note in pieces.
void main() {
  setUp(TranslateSheet.forgetAll);

  CloudAIAdapter adapter(
    List<String> asked,
    String Function(int call) reply, {
    int failFrom = 1 << 30,
  }) {
    var calls = 0;
    return CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      client: MockClient((request) async {
        calls++;
        asked.add(request.body);
        if (calls >= failFrom) return http.Response('{}', 503);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': reply(calls)},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  Future<AppLocalizations> pump(
    WidgetTester tester,
    NexTestHarness h,
    Widget sheet, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(TranslateSheet)));
  }

  String target(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('translation-target')))
      .data!;

  test('the direction is the language the text is not in', () {
    expect(nexTranslationTarget('سلام دنیا'), AiOutputLanguage.english);
    expect(nexTranslationTarget('Hello world'), AiOutputLanguage.persian);
    expect(nexPersianShare('abc'), 0);
    expect(nexPersianShare('سلام'), 1);
  });

  test('a long note goes in pieces of whole paragraphs', () {
    final paragraph = List.filled(60, 'word').join(' ');
    final text = List.filled(12, paragraph).join('\n\n');
    final chunks = CloudAIAdapter.translationChunks(text, limit: 800);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= 800), isTrue);
    expect(chunks.join('\n\n'), text);
    expect(CloudAIAdapter.translationChunks('short'), ['short']);
  });

  for (final locale in ['en', 'fa']) {
    testWidgets('$locale a note in one language: no choice, no failure', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      final asked = <String>[];
      String? accepted;
      final l10n = await pump(
        tester,
        h,
        TranslateSheet(
          text: original.content!,
          preferences: h.preferences,
          services: h.services,
          adapter: adapter(asked, (_) => 'ترجمهٔ فارسی'),
          onAddToCaption: (text) => accepted = text,
        ),
        locale: locale,
      );
      expect(asked, hasLength(1));
      // English in, so Persian out — and no way to ask for English.
      expect(target(tester), l10n.aiOutputLanguagePersian);
      expect(find.byKey(const ValueKey('translation-swap')), findsNothing);
      expect(find.text('ترجمهٔ فارسی'), findsOneWidget);

      await tester.tap(find.text(l10n.copy));
      await tester.pumpAndSettle();
      expect(copied, ['ترجمهٔ فارسی']);
      await tester.tap(find.text(l10n.aiAddToCaption));
      expect(accepted, 'ترجمهٔ فارسی');
      await tester.tap(find.text(l10n.translateSaveAsNote));
      await tester.pumpAndSettle();
      expect(
        (await h.services.timeline()).map((n) => n.content),
        contains('ترجمهٔ فارسی'),
      );
      expect(
        (await h.services.getById(original.id))!.content,
        'Original source',
      );
      expect(tester.takeException(), isNull);

      // Kept for the session: opened again, it is there without a request.
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        h,
        TranslateSheet(
          text: original.content!,
          preferences: h.preferences,
          services: h.services,
          adapter: adapter(asked, (_) => 'unused'),
        ),
        locale: locale,
      );
      expect(asked, hasLength(1));
      expect(find.text('ترجمهٔ فارسی'), findsOneWidget);
      expect(TranslateSheet.hasTranslation(original.content!), isTrue);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a Persian note goes into English', (tester) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final l10n = await pump(
      tester,
      h,
      TranslateSheet(
        text: 'یادداشتی به فارسی',
        preferences: h.preferences,
        services: h.services,
        adapter: adapter([], (_) => 'A note in Persian'),
      ),
    );
    expect(target(tester), l10n.aiOutputLanguageEnglish);
    expect(find.text('A note in Persian'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a note in both offers the other way, and a failed one shows '
      'no old result', (tester) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final asked = <String>[];
    final l10n = await pump(
      tester,
      h,
      TranslateSheet(
        text: 'Meeting notes: جلسهٔ فردا',
        preferences: h.preferences,
        services: h.services,
        adapter: adapter(asked, (_) => 'First way', failFrom: 2),
      ),
    );
    expect(find.text('First way'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('translation-swap')));
    await tester.pumpAndSettle();
    expect(asked, hasLength(2));
    expect(find.text('First way'), findsNothing);
    expect(find.byKey(const ValueKey('translation-failed')), findsOneWidget);
    expect(find.text(l10n.translateSaveAsNote), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
