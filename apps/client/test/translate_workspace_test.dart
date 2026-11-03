import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/translate_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

class _Provider {
  List<String> languages = ['fr'];
  int detections = 0;
  final sources = <String>[];
  int? failOnce;
  Completer<http.Response>? held;

  http.Response reply(String text) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': text},
          'finish_reason': 'stop',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final adapter = CloudAIAdapter(
    config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      final messages = body['messages'] as List;
      if ((messages.first['content'] as String).startsWith(
        'Identify the natural',
      )) {
        detections++;
        return reply(jsonEncode(languages));
      }
      sources.add(messages.last['content'] as String);
      if (sources.length == failOnce) {
        failOnce = null;
        return http.Response('{}', 503);
      }
      if (held != null) {
        final pending = held!;
        held = null;
        return pending.future;
      }
      return reply('Translated part ${sources.length}');
    }),
  );
}

void main() {
  setUp(TranslateSheet.forgetAll);

  Future<AppLocalizations> open(
    WidgetTester tester,
    NexTestHarness h,
    _Provider provider,
    String text, {
    String locale = 'en',
    String? noteId,
    bool glass = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: nexDarkTheme(liquidGlass: glass),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TranslateSheet(
              text: text,
              noteId: noteId,
              preferences: h.preferences,
              services: h.services,
              adapter: provider.adapter,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(TranslateSheet)));
  }

  for (final locale in ['en', 'fa']) {
    testWidgets('$locale: the entire language bar opens one existing picker', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final provider = _Provider();
      final l10n = await open(
        tester,
        h,
        provider,
        'Bonjour le monde',
        locale: locale,
      );
      final bar = find.byKey(const ValueKey('translation-language-bar'));
      final before = tester.getRect(
        find.byKey(const ValueKey('translation-direction')),
      );
      final points = [
        tester.getCenter(find.byKey(const ValueKey('translation-source'))),
        tester.getCenter(find.byKey(const ValueKey('translation-target'))),
        Offset(before.center.dx, before.bottom - 3),
        tester.getCenter(
          find.byKey(const ValueKey('translation-choose-language')),
        ),
      ];
      for (final point in points) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('translation-language-search')),
          findsOneWidget,
        );
        expect(find.text(l10n.translationChooseLanguage), findsOneWidget);
        Navigator.of(
          tester.element(
            find.byKey(const ValueKey('translation-language-search')),
          ),
        ).pop();
        await tester.pumpAndSettle();
      }
      expect(tester.widget<InkWell>(bar).onTap, isNotNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('translation-direction'))),
        before,
      );
      expect(provider.detections, 1);
      expect(provider.sources, ['Bonjour le monde']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$locale detects a third language and defaults to UI language',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        final provider = _Provider();
        final l10n = await open(
          tester,
          h,
          provider,
          'Bonjour le monde',
          locale: locale,
        );
        expect(provider.detections, 1);
        expect(provider.sources, ['Bonjour le monde']);
        expect(
          find.text(locale == 'fa' ? 'فرانسوی' : 'French'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('translation-target')),
          findsOneWidget,
        );
        expect(
          find.text(
            locale == 'fa'
                ? l10n.aiOutputLanguagePersian
                : l10n.aiOutputLanguageEnglish,
          ),
          findsOneWidget,
        );
        expect(find.text('Translated part 1'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await open(tester, h, provider, 'Bonjour le monde', locale: locale);
        expect(
          provider.sources,
          hasLength(1),
          reason: 'reopening reuses the completed job',
        );
        expect(provider.detections, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('same-language default suggests a different language', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final provider = _Provider()..languages = ['en'];
    final l10n = await open(tester, h, provider, 'An English note');
    expect(find.text(l10n.aiOutputLanguagePersian), findsOneWidget);
    expect(find.text(l10n.translationSuggestedLanguage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search finds more languages and remembers explicit selection; RTL/glass/large text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = await NexTestHarness.create(
        preferences: {'ai.translationTarget': 'de'},
      );
      addTearDown(h.dispose);
      final provider = _Provider()..languages = ['fa', 'ru'];
      await open(
        tester,
        h,
        provider,
        'سلام و Привет',
        locale: 'fa',
        glass: true,
      );
      expect(find.text('آلمانی'), findsOneWidget);
      expect(find.text('فارسی + روسی'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('translation-choose-language')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('translation-language-search')),
        '日本',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('translation-language-ja')));
      await tester.pumpAndSettle();
      expect(h.preferences.translationTarget, 'ja');
      expect(provider.detections, 1);
      expect(provider.sources, hasLength(2));
      expect(find.text('ژاپنی'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failure checkpoints successful chunks; retry sends only the missing suffix',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final provider = _Provider()..failOnce = 2;
      final text = List.generate(
        4,
        (i) => '$i ${List.filled(130, 'word').join(' ')}',
      ).join('\n\n');
      final l10n = await open(tester, h, provider, text);
      expect(provider.sources, hasLength(2));
      final first = provider.sources.first;
      final failed = provider.sources.last;
      expect(find.byKey(const ValueKey('translation-failed')), findsOneWidget);
      expect(find.text(l10n.translateSaveAsNote), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await open(tester, h, provider, text);
      expect(
        provider.sources,
        hasLength(2),
        reason: 'reopening does not silently retry a failed job',
      );
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(provider.sources.where((part) => part == first), hasLength(1));
      expect(provider.sources[2], failed);
      expect(provider.detections, 1);
      expect(find.byKey(const ValueKey('translation-failed')), findsNothing);
      expect(find.text(l10n.translateSaveAsNote), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('37,781 characters require consent and translate to completion', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final provider = _Provider();
    final text = List.filled(8000, 'word').join(' ').substring(0, 37781);
    await open(tester, h, provider, text);
    expect(provider.sources, isEmpty);
    expect(provider.detections, 0);
    await tester.tap(find.byKey(const ValueKey('translation-continue')));
    await tester.pumpAndSettle();
    expect(provider.sources.length, NexTranslationChunk.split(text).length);
    expect(provider.detections, 1);
    expect(find.byKey(const ValueKey('translation-failed')), findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TranslateSheet)),
    );
    expect(find.text(l10n.translateSaveAsNote), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reopening during a live request attaches without duplicate requests',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final response = Completer<http.Response>();
      final provider = _Provider()..held = response;
      await open(tester, h, provider, 'A pending source', noteId: 'note');
      expect(provider.sources, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await open(tester, h, provider, 'A pending source', noteId: 'note');
      expect(provider.sources, hasLength(1));
      response.complete(provider.reply('Completed after reopening'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Completed after reopening'), findsOneWidget);
      expect(provider.detections, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editing the source invalidates pending output', (tester) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final response = Completer<http.Response>();
    final old = _Provider()..held = response;
    await open(tester, h, old, 'Old source', noteId: 'note');
    final newer = _Provider();
    await open(tester, h, newer, 'New source', noteId: 'note');
    response.complete(old.reply('Stale output'));
    await tester.pumpAndSettle();
    expect(find.text('Stale output'), findsNothing);
    expect(newer.sources, ['New source']);
    expect(TranslateSheet.hasTranslation('Old source'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('oversize text explains the limit without making any request', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final provider = _Provider();
    await open(tester, h, provider, List.filled(100001, 'x').join());
    expect(provider.detections, 0);
    expect(provider.sources, isEmpty);
    expect(find.byKey(const ValueKey('translation-too-large')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
