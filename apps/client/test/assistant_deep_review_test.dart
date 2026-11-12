import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

http.Response _reply(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

/// The assistant review that shipped with Nex 2.6.20: on-device stop,
/// caption-aware labels, and honest failure words on the lookup round.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create();
    await harness.preferences.setAiEnabled(true);
    addTearDown(() => harness.dispose());
  });

  Future<void> openSheet(
    WidgetTester tester, {
    required http.Client client,
    Note? focus,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiChatSheet(
            preferences: harness.preferences,
            services: harness.services,
            history: harness.preferences.chatHistory,
            client: client,
            focus: focus,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    final field = find.descendant(
      of: find.byType(AiChatSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, text);
    // Let the mic→send switch finish before the tap: mid-transition the
    // exiting mic still covers the spot, and the tap lands on it instead.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send')));
    // The thinking animation never settles, so advance by hand — the same
    // discipline assistant_cancellation_test uses.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('an on-device answer can be stopped', () {
    testWidgets('stop drops the wait and discards the late reply', (
      tester,
    ) async {
      // No provider, a bound model: the request goes to the phone.
      await harness.preferences.setAiProvider(const AiProviderConfig());
      final model = _GatedModel();
      ChatAdapterBinding.bind(model);
      addTearDown(ChatAdapterBinding.reset);
      // Stands in for the network; never used on this path.
      await openSheet(
        tester,
        client: MockClient((_) async => _reply('unused')),
      );

      await send(tester, 'hello?');
      expect(model.asked, 1);
      // The one control the wait had been missing: with no provider there was
      // no stop button at all, and a cold model held the sheet for its whole
      // budget with no way out.
      expect(find.byKey(const ValueKey('stop-chat')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-thinking')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stop-chat')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Response stopped'), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-thinking')), findsNothing);

      // The native call has no cancellation; when it lands anyway, its reply
      // is dropped rather than answering a question that was abandoned.
      model.answer('a late reply lands');
      await tester.pumpAndSettle();
      expect(find.textContaining('a late reply lands'), findsNothing);
      expect(find.textContaining('Response stopped'), findsOneWidget);

      // And the conversation is not wedged: a fresh question still answers.
      await send(tester, 'again?');
      expect(model.asked, 2);
      model.answer('a fresh answer lands');
      await tester.pumpAndSettle();
      expect(find.textContaining('a fresh answer lands'), findsOneWidget);
      expect(find.textContaining('Response stopped'), findsNothing);
    });
  });

  group('a captioned note names itself by its caption', () {
    testWidgets('the About line and the citation chip both use it', (
      tester,
    ) async {
      await harness.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
      );
      final now = DateTime.now().toUtc();
      final note = Note(
        id: '018f0000-0000-7000-8000-000000000001',
        type: NoteType.photo,
        // The person's own line on it — the only words the note has. Before
        // this change both labels fell through to the kind name ("Photo").
        caption: 'the whiteboard after the planning day',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      await openSheet(
        tester,
        focus: note,
        client: MockClient(
          (_) async => _reply(
            'It looks full.\nSources: [018f0000-0000-7000-8000-000000000001]',
          ),
        ),
      );

      // The header says what the chat is about.
      expect(
        find.textContaining('the whiteboard after the planning day'),
        findsWidgets,
      );

      await send(tester, 'what is on it?');
      await tester.pumpAndSettle();
      // The grounding chip under the answer, same words the card headlines.
      expect(
        find.widgetWithText(
          ActionChip,
          'the whiteboard after the planning day',
        ),
        findsOneWidget,
      );
      expect(find.text('It looks full.'), findsOneWidget);
    });
  });

  group('the lookup round fails in its own words', () {
    testWidgets('a rate limit there is called a rate limit', (tester) async {
      await harness.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
      );
      var calls = 0;
      await openSheet(
        tester,
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return _reply('```nex\n{"action":"tags"}\n```');
          }
          return http.Response(
            jsonEncode({
              'error': {'message': 'quota exceeded until tomorrow'},
            }),
            429,
          );
        }),
      );

      await send(tester, 'what tags do I have?');
      await tester.pumpAndSettle();
      // Two requests: the question, then the lookup it asked for.
      expect(calls, 2);
      // The second request's failure used to collapse into "no answer came
      // back", which is advice for the wrong problem.
      expect(
        find.textContaining('The service limit was reached'),
        findsOneWidget,
      );
      expect(find.textContaining('No answer came back'), findsNothing);
      expect(
        find.textContaining('quota exceeded until tomorrow'),
        findsNothing,
      );
    });
  });
}

/// An on-device model whose answers are handed over by the test, so a reply
/// can be made to arrive after the person has given up on it.
class _GatedModel implements ChatAdapter {
  final gates = <Completer<ChatResponse>>[];

  int get asked => gates.length;

  void answer(String text) => gates.last.complete(ChatResponse(content: text));

  @override
  bool get available => true;

  @override
  Future<void>? warmUp() => null;

  @override
  Future<void>? release() => null;

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    final gate = Completer<ChatResponse>();
    gates.add(gate);
    return gate.future;
  }
}
