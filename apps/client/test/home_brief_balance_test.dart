import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

const _notes = [
  'Nex roadmap: improve search and home widgets.',
  'AI editing: preserve the delivery date of 14 November.',
  'Text files: add expanded Markdown and DOCX previews.',
  'Vazho project: build a language learning assistant.',
  'Medicine packaging: approve the catalogue print colours.',
  'Print order: call the printer before dispatch.',
];

Future<void> _seed(NexTestHarness h, NexBriefStyle style) async {
  await h.preferences.setSponsorAttemptedAt(DateTime.now());
  await h.preferences.setShowGreeting(false);
  await h.preferences.setBriefStyle(style);
  await h.preferences.setBriefLength(NexBriefLength.long);
  for (final note in _notes) {
    await h.services.captureText(note);
  }
  await h.preferences.setModuleOn('habits', true);
  await h.preferences.setBriefUseHabits(true);
  final store = NexModuleStore(h.services, 'habits');
  for (final name in [
    'Drink water',
    'Sleep on time',
    'Less phone time',
    'Exercise',
  ]) {
    await store.put('habit', name, {
      'name': name,
      'schedule': 'daily',
      'goal': name == 'Drink water' ? 8 : 1,
      'unit': name == 'Drink water' ? 'glasses' : '',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
  final day = dateKeyOf(DateTime.now());
  await store.put('check', HabitCheck.idFor('Drink water', day), {
    'habit': 'Drink water',
    'date': day,
    'amount': 4,
    'at': DateTime.now().toIso8601String(),
  });
}

void main() {
  testWidgets('Full plain report keeps ordinary notes alongside habits', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await _seed(h, NexBriefStyle.report);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('timeline-recap'));
    for (final note in _notes) {
      expect(
        find.descendant(of: card, matching: find.textContaining(note)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: card, matching: find.textContaining('Drink water')),
      findsOneWidget,
    );
    for (final length in NexBriefLength.values) {
      await h.preferences.setBriefLength(length);
      await tester.pumpAndSettle();
      final content = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .map((widget) => widget.data ?? '')
          .where(
            (text) =>
                _notes.any(text.contains) ||
                [
                  'Drink water',
                  'Sleep on time',
                  'Exercise',
                  'Less phone time',
                ].any(text.contains),
          )
          .toList();
      expect(content, hasLength(length.lines));
      // Notes spend the budget first; habits fill only the remaining rows.
      // Short and medium reports must not displace a note to reserve progress.
      final noteCount = length.lines.clamp(0, _notes.length);
      expect(
        content.where((text) => _notes.any(text.contains)),
        hasLength(noteCount),
      );
      for (final text in content.take(noteCount)) {
        expect(_notes.any(text.contains), isTrue);
      }
      expect(
        content.any((text) => text.contains('4/8 glasses')),
        length.lines > _notes.length,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final style in NexBriefStyle.values.where((s) => s.usesModel)) {
    testWidgets(
      'Full ${style.name} sends notes and habits once and shows both',
      (tester) async {
        final previousHttp = HttpOverrides.current;
        HttpOverrides.global = null;
        final requests = <Map<String, dynamic>>[];
        late HttpServer server;
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests.add(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>,
            );
            final reply = style.statesFacts
                ? '💡 Call the printer after approving the catalogue colours.'
                : [
                    for (final note in _notes) '📝 $note',
                    '💧 Drink water: 4/8 glasses.',
                    '🌙 Sleep on time is left for today.',
                  ].join('\n');
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': reply},
                    'finish_reason': 'stop',
                  },
                ],
              }),
            );
            await request.response.close();
          });
        });
        final h = await NexTestHarness.create();
        addTearDown(() async {
          HttpOverrides.global = previousHttp;
          await h.dispose();
          await server.close(force: true);
        });
        await _seed(h, style);
        await h.preferences.setAiEnabled(true);
        await h.preferences.setAiProvider(
          AiProviderConfig(
            provider: AiProvider.custom,
            apiKey: 'fixture',
            model: 'fixture',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
          ),
        );
        await h.preferences.setBriefInstruction(
          'Read my notes and include useful habit progress.',
        );
        await tester.pumpWidget(h.app());
        for (var i = 0; i < 50 && h.preferences.lastRecap == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(requests, hasLength(1));
        final messages = requests.single['messages'] as List;
        final sent = messages.last['content'] as String;
        for (final note in _notes) {
          expect(sent, contains(note));
          expect(h.preferences.lastRecap, contains(note));
        }
        expect(sent, contains('HABIT'));
        expect(h.preferences.lastRecap, contains('Drink water'));
        expect(h.preferences.lastRecap, contains('4/8'));
        expect(
          h.preferences.lastRecap!.split('\n').length,
          lessThanOrEqualTo(8),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
