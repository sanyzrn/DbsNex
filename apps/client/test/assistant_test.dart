import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:path/path.dart' as p;

import 'package:nex_client/l10n/app_localizations.dart';

import 'support/in_process_db.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/assistant_actions.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('assistant actions', () {
    test('reads a fenced action block', () {
      final action = parseAssistantAction('''
```nex
{"action": "create", "text": "buy oat milk"}
```
''');
      expect(action?.kind, AssistantActionKind.create);
      expect(action?.text, 'buy oat milk');
    });

    test('survives the fences models actually write', () {
      // Prose in front of the block, and `json` instead of `nex` — both
      // forbidden by the prompt and both routinely produced anyway.
      final action = parseAssistantAction('''
Sure, here you go:

```json
{"action": "delete", "id": "n-42"}
```
''');
      expect(action?.kind, AssistantActionKind.delete);
      expect(action?.noteId, 'n-42');
    });

    test('an answer that merely mentions JSON is not an action', () {
      expect(
        parseAssistantAction('You wrote three notes about the cooler.'),
        isNull,
      );
      expect(parseAssistantAction('```\nnot json at all\n```'), isNull);
    });

    test('a half-written action is refused rather than half-applied', () {
      // An edit with no id would otherwise be indistinguishable from an edit
      // of whichever note happened to be first.
      expect(parseAssistantAction('{"action":"edit","text":"x"}'), isNull);
      expect(parseAssistantAction('{"action":"delete"}'), isNull);
      // A tag action changing nothing is not an action.
      expect(
        parseAssistantAction('{"action":"tag","id":"n1","add":[]}'),
        isNull,
      );
    });

    test('tags split into what is added and what is taken away', () {
      final action = parseAssistantAction(
        '{"action":"tag","id":"n1","add":["work","urgent"],"remove":["home"]}',
      );
      expect(action?.kind, AssistantActionKind.tag);
      expect(action?.addTags, ['work', 'urgent']);
      expect(action?.removeTags, ['home']);
    });

    test('prose around a block survives without the block', () {
      const reply =
          'Deleting that one.\n```nex\n{"action":"delete","id":"a"}\n```';
      expect(withoutActionBlock(reply), 'Deleting that one.');
    });
  });

  group('the system prompt keeps the promises Settings makes', () {
    CloudAIAdapter adapter() => CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'secret',
      ),
    );

    test('notes-only says so, and off it does not', () {
      final on = adapter().chatSystemPrompt(
        const AiChatOptions(notesContext: '[n1] a note'),
      );
      expect(on, contains('only from'));
      expect(on, contains('[n1] a note'));

      final off = adapter().chatSystemPrompt(
        const AiChatOptions(notesOnly: false, notesContext: '[n1] a note'),
      );
      expect(off, isNot(contains('only from')));
    });

    test('the action vocabulary is absent unless acting is on', () {
      expect(
        adapter().chatSystemPrompt(const AiChatOptions()),
        isNot(contains('"action"')),
      );
      expect(
        adapter().chatSystemPrompt(const AiChatOptions(canAct: true)),
        contains('"action"'),
      );
    });

    test('answer length reaches the prompt, not just the token budget', () {
      expect(
        adapter().chatSystemPrompt(
          const AiChatOptions(length: AiAnswerLength.brief),
        ),
        contains('one or two sentences'),
      );
      expect(
        AiAnswerLength.brief.maxTokens,
        lessThan(AiAnswerLength.full.maxTokens),
      );
      expect(
        AiCreativity.precise.temperature,
        lessThan(AiCreativity.inventive.temperature),
      );
    });

    test('no notes shared is a working state, not a broken one', () {
      final prompt = adapter().chatSystemPrompt(const AiChatOptions());
      expect(prompt, contains('no notes yet'));
    });
  });

  group('chat history', () {
    late ChatHistory history;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      history = ChatHistory(await SharedPreferences.getInstance());
    });

    List<ChatMessage> exchange(String question) => [
      ChatMessage(role: ChatRole.user, content: question),
      const ChatMessage(role: ChatRole.assistant, content: 'an answer'),
    ];

    test('saving twice under one id keeps one thread, not two', () async {
      await history.save('t1', exchange('first'));
      await history.save('t1', [...exchange('first'), ...exchange('second')]);
      expect(history.threads.length, 1);
      expect(history.threads.single.messages.length, 4);
      // The list is named after the opening question, whatever came after.
      expect(history.threads.single.title, 'first');
    });

    test('newest first, and bounded', () async {
      for (var i = 0; i < ChatHistory.maxThreads + 5; i++) {
        await history.save('t$i', exchange('question $i'));
      }
      expect(history.threads.length, ChatHistory.maxThreads);
      expect(history.threads.first.title, contains('question 34'));
    });

    test('a long conversation keeps its opening and its end', () async {
      final long = [
        for (var i = 0; i < ChatHistory.maxMessagesPerThread + 20; i++)
          ChatMessage(role: ChatRole.user, content: 'turn $i'),
      ];
      await history.save('t1', long);
      final kept = history.threads.single.messages;
      expect(kept.length, ChatHistory.maxMessagesPerThread);
      expect(kept.first.content, 'turn 0');
      expect(kept.last.content, 'turn ${long.length - 1}');
    });

    test(
      'survives a restart, and a corrupt store is empty not fatal',
      () async {
        await history.save('t1', exchange('remembered'));
        final reloaded = ChatHistory(await SharedPreferences.getInstance());
        expect(reloaded.threads.single.title, 'remembered');

        SharedPreferences.setMockInitialValues({'ai.chatThreads': 'not json'});
        final broken = ChatHistory(await SharedPreferences.getInstance());
        expect(broken.threads, isEmpty);
      },
    );

    test('deleting one leaves the rest', () async {
      await history.save('t1', exchange('one'));
      await history.save('t2', exchange('two'));
      await history.remove('t1');
      expect(history.threads.single.title, 'two');
      await history.clear();
      expect(history.threads, isEmpty);
    });
  });

  group('an action the model asks for is never applied on arrival', () {
    late Directory tmp;
    late NexServices services;
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('nex_assistant_');
      final dbPath = p.join(tmp.path, 'nex.sqlite');
      final mediaDir = p.join(tmp.path, 'media');
      final backupDir = p.join(tmp.path, 'backups');
      Directory(mediaDir).createSync(recursive: true);
      Directory(backupDir).createSync(recursive: true);
      services = NexServices.forTest(
        worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
        deviceId: 'test',
        preferences: await NexPreferences.load(),
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: dbPath,
        mediaDir: mediaDir,
        backupDir: backupDir,
      );
      preferences = await NexPreferences.load();
      await preferences.setAiEnabled(true);
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      );
    });

    tearDown(() async {
      await services.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// A provider that answers every question with the same reply.
    http.Client replying(String content) => MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );

    Future<void> openSheet(
      WidgetTester tester, {
      required http.Client client,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => AiChatSheet.show(
                    context,
                    preferences: preferences,
                    services: services,
                    history: preferences.chatHistory,
                    client: client,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a delete waits for the button, then does it', (tester) async {
      final note = (await services.captureText('the cooler is broken'))!;
      await tester.pumpAndSettle();

      await openSheet(
        tester,
        client: replying('```nex\n{"action":"delete","id":"${note.id}"}\n```'),
      );
      await tester.enterText(
        find.byType(TextField).last,
        'delete the cooler note',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // The reply asked for a delete. Nothing has happened yet.
      expect(await services.getById(note.id), isNotNull);
      // And the raw JSON is not what the user is looking at.
      expect(find.textContaining('"action"'), findsNothing);

      final confirm = find.widgetWithText(FilledButton, 'Do it');
      expect(confirm, findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(await services.getById(note.id), isNull);
    });

    testWidgets('cancelling leaves the note alone', (tester) async {
      final note = (await services.captureText('keep me'))!;
      await tester.pumpAndSettle();

      await openSheet(
        tester,
        client: replying('```nex\n{"action":"delete","id":"${note.id}"}\n```'),
      );
      await tester.enterText(find.byType(TextField).last, 'delete it');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Do it'), findsNothing);
      expect(await services.getById(note.id), isNotNull);
    });

    testWidgets('an ordinary answer offers no button at all', (tester) async {
      await services.captureText('a note');
      await tester.pumpAndSettle();

      await openSheet(tester, client: replying('You wrote about the cooler.'));
      await tester.enterText(find.byType(TextField).last, 'what did I write?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text('You wrote about the cooler.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Do it'), findsNothing);
    });
  });
}
