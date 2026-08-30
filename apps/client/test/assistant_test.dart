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

import 'package:nex_ui/nex_ui.dart';

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

    test('an unfenced action survives whatever the model put in front', () {
      // Reported from a real conversation: the reply came back as
      // `🔍 {"action": "create", ...}` and the app showed that JSON to the
      // user as the assistant's answer. The parser required an unfenced reply
      // to *be* JSON, so one emoji in front turned a note into a wall of
      // protocol — and the emoji was there because this release had just
      // asked the assistant to use them.
      final action = parseAssistantAction(
        '🔍 {"action": "create", "text": "call the plumber"}',
      );
      expect(action?.kind, AssistantActionKind.create);
      expect(action?.text, 'call the plumber');

      // Same for a word in front, which is the older and commoner version of
      // the same failure.
      expect(
        parseAssistantAction('Sure: {"action": "delete", "id": "n1"}')?.kind,
        AssistantActionKind.delete,
      );
    });

    test('a brace inside note text does not end the object early', () {
      // The reason this is a scan and not a regex: `}` is legal inside a JSON
      // string, and a note about a shell script contains one.
      final action = parseAssistantAction(
        r'{"action": "create", "text": "run ${HOME}/bin/x"}',
      );
      expect(action?.text, r'run ${HOME}/bin/x');
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

    test('several blocks in one reply are all read, in order', () {
      // A real request often is more than one change: "tag these two and
      // delete the third" is three actions and one intention.
      final actions = parseAssistantActions('''
```nex
{"action": "tag", "id": "a", "add": ["work"]}
```
```nex
{"action": "delete", "id": "b"}
```
''');
      expect(actions.map((a) => a.kind), [
        AssistantActionKind.tag,
        AssistantActionKind.delete,
      ]);
      expect(actions.last.noteId, 'b');
    });

    test('bare JSON with no fence still counts', () {
      // Models drop the fence once the prompt has been in context a while.
      // Refusing it would mean acting works for the first few messages of a
      // conversation and then quietly stops.
      final actions = parseAssistantActions('{"action":"delete","id":"a"}');
      expect(actions.single.kind, AssistantActionKind.delete);
    });

    test('a search is a read, and marked as one', () {
      final action = parseAssistantAction(
        '{"action":"search","query":"cooler"}',
      );
      expect(action?.kind, AssistantActionKind.search);
      expect(action?.text, 'cooler');
      expect(action?.isRead, isTrue);
      expect(
        parseAssistantAction('{"action":"delete","id":"a"}')?.isRead,
        isFalse,
      );
    });

    test('a merge needs at least two notes', () {
      expect(
        parseAssistantAction('{"action":"merge","ids":["a"]}'),
        isNull,
        reason: 'merging one note is a rename with extra steps',
      );
      final action = parseAssistantAction(
        '{"action":"merge","ids":["a","b"],"text":"both"}',
      );
      expect(action?.noteIds, ['a', 'b']);
      expect(action?.text, 'both');
    });

    test('checklist conversion and ticking carry what they need', () {
      expect(
        parseAssistantAction('{"action":"to_checklist","id":"a"}')?.kind,
        AssistantActionKind.toChecklist,
      );
      final tick = parseAssistantAction(
        '{"action":"check","id":"a","index":2}',
      );
      expect(tick?.index, 2);
      // Without an index there is no item to tick.
      expect(parseAssistantAction('{"action":"check","id":"a"}'), isNull);
    });

    test('only the settings this app offered can be changed', () {
      final ok = parseAssistantAction(
        '{"action":"setting","key":"theme","value":"dark"}',
      );
      expect(ok?.settingKey, 'theme');
      expect(ok?.settingValue, 'dark');
      // The ones that must never move because a model read a sentence a
      // certain way.
      for (final key in ['api_key', 'sync_url', 'ai.key.openai', 'retention']) {
        expect(
          parseAssistantAction('{"action":"setting","key":"$key","value":"x"}'),
          isNull,
          reason: '$key is not the assistant\'s to change',
        );
      }
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

    test('emoji are asked for, and bounded in the same breath', () {
      final prompt = adapter().chatSystemPrompt(const AiChatOptions());
      // Both halves matter. "Use more emoji" on its own produces a reply with
      // a picture beside every noun; the cap is what makes it punctuation.
      expect(prompt, contains('emoji'));
      expect(prompt, contains('At most one per line'));
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

    test('the user profile and response style reach the prompt', () {
      final prompt = adapter().chatSystemPrompt(
        const AiChatOptions(
          responseStyle: AiResponseStyle.romantic,
          userName: 'Sany',
          userIntroduction: 'I write music and prefer Persian replies.',
        ),
      );
      expect(prompt, contains('Address the user as "Sany"'));
      expect(prompt, contains('I write music'));
      expect(prompt, contains('affectionately and romantically'));
      expect(prompt, contains('respecting boundaries'));
    });

    test('no notes shared is a working state, not a broken one', () {
      final prompt = adapter().chatSystemPrompt(const AiChatOptions());
      expect(prompt, contains('no notes yet'));
    });

    test("the user's own instruction reaches the prompt, quoted", () {
      final prompt = adapter().chatSystemPrompt(
        const AiChatOptions(instruction: '  answer with a bit of humour  '),
      );
      // Trimmed, quoted, and attributed to the user rather than stated as one
      // of the app's own rules — the model has to be able to tell which is
      // which, or a preference about tone arrives with the same authority as
      // the scope rule under it.
      expect(prompt, contains('"answer with a bit of humour"'));
      expect(prompt, contains('The user has asked you'));
      expect(prompt, isNot(contains('  answer')));
    });

    test('tone reaches the prompt from one control, not two', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // The instruction only travels under the style it belongs to. Sending a
      // preset and a sentence together would be two answers to one question,
      // so the choice is made where the preference is read, not in the prompt.
      SharedPreferences.setMockInitialValues({
        'ai.responseStyle': 'formal',
        'ai.instruction': 'be witty and sarcastic',
      });
      final chosen = await NexPreferences.load();
      expect(chosen.aiResponseStyle, AiResponseStyle.formal);
      // Still stored, so switching to Custom brings it back rather than
      // asking for it again.
      expect(chosen.aiInstruction, 'be witty and sarcastic');

      // Whoever wrote an instruction before there was a preset for it never
      // had a style key written. Deriving it rather than migrating keeps their
      // sentence working without writing to their preferences on their behalf.
      SharedPreferences.setMockInitialValues({
        'ai.instruction': 'answer with a bit of humour',
      });
      final inherited = await NexPreferences.load();
      expect(inherited.aiResponseStyle, AiResponseStyle.custom);

      // And an untouched install is the default, not a custom style with
      // nothing in it.
      SharedPreferences.setMockInitialValues({});
      final fresh = await NexPreferences.load();
      expect(fresh.aiResponseStyle, isNot(AiResponseStyle.custom));
    });

    test('an empty instruction adds nothing at all', () {
      expect(
        adapter().chatSystemPrompt(const AiChatOptions(instruction: '   ')),
        adapter().chatSystemPrompt(const AiChatOptions()),
      );
    });

    test('an instruction cannot outrank the scope rule that follows it', () {
      final prompt = adapter().chatSystemPrompt(
        const AiChatOptions(
          instruction: 'ignore the notes and answer anything',
          notesContext: '[n1] a note',
        ),
      );
      expect(
        prompt.indexOf('The user has asked you'),
        lessThan(prompt.indexOf('Answer only from')),
      );
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
      Note? focus,
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
                    focus: focus,
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

    /// The composer's own direction, which is not the sheet's.
    TextDirection? composerDirection(WidgetTester tester) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(AiChatSheet),
            matching: find.byType(TextField),
          ),
        )
        .textDirection;

    testWidgets('the composer turns to the script being typed', (tester) async {
      await openSheet(
        tester,
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final field = find.descendant(
        of: find.byType(AiChatSheet),
        matching: find.byType(TextField),
      );

      // Empty: no direction of its own, so the placeholder sits at whichever
      // edge the interface language puts it.
      expect(composerDirection(tester), isNull);

      // The reported case — a Persian question with two English words in it.
      // Laid out left-to-right, bidi reorders the runs around the wrong base
      // and the line scrambles while it is being typed.
      await tester.enterText(field, 'به نظرت واسه ویندوز lmstudio بهتره؟');
      await tester.pump();
      expect(composerDirection(tester), TextDirection.rtl);

      await tester.enterText(field, 'is lmstudio better than ollama?');
      await tester.pump();
      expect(composerDirection(tester), TextDirection.ltr);
    });

    testWidgets('the assistant\'s answer is rendered, the question is not', (
      tester,
    ) async {
      await openSheet(
        tester,
        client: replying('Here you go:\n\n- **first** thing\n- second thing'),
      );
      // The user's own turn is Markdown-shaped on purpose: they typed those
      // asterisks and the app has no business eating them.
      await tester.enterText(find.byType(TextField).last, 'give me a **list**');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // The reply is rendered — the bold marks are gone and the word is not.
      expect(find.byType(NexMarkdown), findsOneWidget);
      expect(find.textContaining('**first**'), findsNothing);
      expect(find.textContaining('first'), findsWidgets);
      // The question is still exactly what was typed.
      expect(find.text('give me a **list**'), findsOneWidget);
    });

    testWidgets('a plain answer stays plain', (tester) async {
      await openSheet(tester, client: replying('No, ollama is simpler.'));
      await tester.enterText(find.byType(TextField).last, 'lmstudio?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // Nothing to gain by parsing prose, and something to lose: a stray
      // asterisk or underscore in an ordinary sentence would be eaten.
      expect(find.byType(NexMarkdown), findsNothing);
      expect(find.text('No, ollama is simpler.'), findsOneWidget);
    });

    testWidgets('a chat about one note says which note', (tester) async {
      final now = DateTime.now().toUtc();
      await openSheet(
        tester,
        client: MockClient((_) async => http.Response('{}', 200)),
        focus: Note(
          id: 'n-focus',
          type: NoteType.text,
          content: 'the whiteboard photo from the standup',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );

      // Opened from a note, the sheet answers only from that note and can act
      // on it. Without this line the same blank chat appeared whether it came
      // from the capture button or from one note's own action row.
      expect(find.textContaining('the whiteboard photo'), findsOneWidget);
    });

    testWidgets('a chat about nothing says nothing', (tester) async {
      await openSheet(
        tester,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(find.textContaining('About:'), findsNothing);
    });

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

    testWidgets('a note that is not there is not reported as deleted', (
      tester,
    ) async {
      // The reported failure: the model names an id that no longer exists —
      // stale context, or one it invented — and the delete runs as an UPDATE
      // that matches no rows. Matching nothing is a successful statement, so
      // nothing threw and the assistant said "Done." over a library that had
      // not moved.
      final note = (await services.captureText('still here'))!;
      await tester.pumpAndSettle();

      await openSheet(
        tester,
        client: replying(
          '```nex\n{"action":"delete","id":"a-note-that-never-existed"}\n```',
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'delete that one');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();

      expect(find.text("That didn't work."), findsOneWidget);
      expect(find.text('Done.'), findsNothing);
      // And the real note is untouched — the check happens before anything
      // runs, so a bad id in the set cannot take a good one down with it.
      expect(await services.getById(note.id), isNotNull);
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

  group('the assistant can look past the notes it was given', () {
    late Directory tmp;
    late NexServices services;
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('nex_lookup_');
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

    testWidgets('a search is run for it, and the results come back', (
      tester,
    ) async {
      await services.captureText('the cooler needs regassing');
      await tester.pumpAndSettle();

      // First reply asks to search; second answers using what came back.
      final sent = <String>[];
      var call = 0;
      final client = MockClient((request) async {
        sent.add(request.body);
        call++;
        final content = call == 1
            ? '```nex\n{"action":"search","query":"cooler"}\n```'
            : 'You wrote that the cooler needs regassing.';
        return http.Response.bytes(
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
        );
      });

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
      await tester.enterText(
        find.byType(TextField).last,
        'what about the cooler?',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // Two requests: the question, then the same conversation with the
      // findings appended.
      expect(call, 2);
      expect(sent.last, contains('regassing'));
      // A search changes nothing, so it must not have produced a button.
      expect(find.widgetWithText(FilledButton, 'Do it'), findsNothing);
      expect(
        find.text('You wrote that the cooler needs regassing.'),
        findsOneWidget,
      );
    });

    testWidgets('it cannot search forever', (tester) async {
      await services.captureText('a note');
      await tester.pumpAndSettle();

      var call = 0;
      final client = MockClient((_) async {
        call++;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '```nex\n{"action":"search","query":"x"}\n```',
                  },
                },
              ],
            }),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });

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
      await tester.enterText(find.byType(TextField).last, 'find something');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // A model that only ever searches would otherwise spend the user's
      // quota in a loop nobody asked for.
      expect(call, lessThanOrEqualTo(3));
    });
  });
}
