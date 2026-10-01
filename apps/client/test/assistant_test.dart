import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:path/path.dart' as p;

import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/l10n/app_localizations.dart';

import 'support/in_process_db.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('assistant actions', () {
    test('one action can name several notes, and becomes one per note', () {
      final actions = parseAssistantActions(
        '```nex\n{"action": "tag", "ids": ["a", "b", "c"], "add": ["work"]}\n```',
      );
      expect(actions.map((a) => a.kind), everyElement(AssistantActionKind.tag));
      expect(actions.map((a) => a.noteId), ['a', 'b', 'c']);
      expect(actions.first.addTags, ['work']);
    });

    test('notes go into a thread by name; a merge keeps its ids together', () {
      final thread = parseAssistantAction(
        '{"action": "thread", "ids": ["a", "b"], "name": "Trip"}',
      );
      expect(thread?.kind, AssistantActionKind.thread);
      expect(thread?.noteIds, ['a', 'b']);
      expect(thread?.threadName, 'Trip');
      expect(thread?.isRead, isFalse);
      final merge = parseAssistantActions(
        '{"action": "merge", "ids": ["a", "b"], "text": "both"}',
      );
      expect(merge.single.noteIds, ['a', 'b']);
    });

    test('a tag, a thread or the thread list can be read without asking', () {
      final tag = parseAssistantAction('{"action": "search", "tag": "work"}');
      expect(tag?.kind, AssistantActionKind.search);
      expect(tag?.tagName, 'work');
      expect(tag?.isRead, isTrue);
      final thread = parseAssistantAction(
        '{"action": "search", "thread": "Trip"}',
      );
      expect(thread?.threadName, 'Trip');
      final threads = parseAssistantAction('{"action": "threads"}');
      expect(threads?.kind, AssistantActionKind.threads);
      expect(threads?.isRead, isTrue);
    });

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

    test('a reminder is a date and a repeat', () {
      // The verb an assistant is actually for, and the one this protocol was
      // missing while the daily brief was built almost entirely out of what
      // is due.
      final action = parseAssistantAction(
        '{"action":"remind","id":"n-1","at":"2026-03-14T09:00",'
        '"repeat":"weekly"}',
      );
      expect(action?.kind, AssistantActionKind.remind);
      expect(action?.noteId, 'n-1');
      expect(action?.at, DateTime(2026, 3, 14, 9));
      expect(action?.at?.isUtc, isFalse, reason: 'nine means nine here');
      expect(action?.repeat, NoteRepeat.weekly);
    });

    test('a new note can carry its reminder', () {
      // "Remind me on Saturday at nine to see the doctor" had no way
      // through: remind needs an id, and the note did not exist yet.
      final action = parseAssistantAction(
        '{"action":"create","text":"See the doctor",'
        '"at":"2026-03-14T09:00","repeat":"weekly"}',
      );
      expect(action?.kind, AssistantActionKind.create);
      expect(action?.text, 'See the doctor');
      expect(action?.at, DateTime(2026, 3, 14, 9));
      expect(action?.repeat, NoteRepeat.weekly);
      expect(
        parseAssistantAction(
          '{"action":"create","text":"See the doctor","at":"saturday"}',
        ),
        isNull,
        reason: 'saved without the reminder asked for would look done',
      );
      expect(
        parseAssistantAction('{"action":"create","text":"plain"}')?.at,
        isNull,
      );
    });

    test('a reminder with no date is the one that cancels it', () {
      final action = parseAssistantAction('{"action":"remind","id":"n-1"}');
      expect(action?.kind, AssistantActionKind.remind);
      expect(action?.at, isNull);
    });

    test('a date that cannot be read is refused, not treated as a cancel', () {
      // The failure this prevents is the worst one available here: the user
      // asked for a reminder, the model wrote a date wrong, and the app
      // silently removed the reminder they already had.
      expect(
        parseAssistantAction('{"action":"remind","id":"n-1","at":"friday"}'),
        isNull,
      );
      expect(
        parseAssistantAction('{"action":"remind","id":"n-1","at":""}'),
        isNull,
      );
    });

    test('an unknown repeat is once, not a parse failure', () {
      final action = parseAssistantAction(
        '{"action":"remind","id":"n-1","at":"2026-03-14T09:00",'
        '"repeat":"fortnightly"}',
      );
      expect(action?.repeat, NoteRepeat.once);
    });

    test('pin goes both ways, and defaults to pinning', () {
      expect(
        parseAssistantAction('{"action":"pin","id":"n-1"}')?.flag,
        isTrue,
        reason: '"pin this" said which one it meant',
      );
      expect(
        parseAssistantAction(
          '{"action":"pin","id":"n-1","pinned":false}',
        )?.flag,
        isFalse,
      );
      final unpin = parseAssistantAction('{"action":"unpin","id":"n-1"}');
      expect(unpin?.kind, AssistantActionKind.pin);
      expect(unpin?.flag, isFalse);
    });

    test('a title with no text clears it', () {
      expect(
        parseAssistantAction(
          '{"action":"title","id":"n-1","text":"Boiler"}',
        )?.text,
        'Boiler',
      );
      final cleared = parseAssistantAction('{"action":"title","id":"n-1"}');
      expect(cleared?.kind, AssistantActionKind.title);
      expect(cleared?.text, isNull);
    });

    test('a restore names a note that is deliberately not in the library', () {
      final action = parseAssistantAction('{"action":"restore","id":"n-9"}');
      expect(action?.kind, AssistantActionKind.restore);
      expect(action?.noteId, 'n-9');
    });

    test('a create with items is a checklist, not a note with lines in it', () {
      // "A shopping list with bread, milk and eggs" used to come back as a
      // text note — which looks almost right and has nothing to tick.
      final action = parseAssistantAction(
        '{"action":"create","items":["bread","milk","eggs"]}',
      );
      expect(action?.kind, AssistantActionKind.create);
      expect(action?.items, ['bread', 'milk', 'eggs']);
      // And still carries the text, so the confirmation card can show what
      // is about to be written without knowing it is a checklist.
      expect(action?.text, 'bread\nmilk\neggs');
    });

    test('a tag rename needs two different names', () {
      final action = parseAssistantAction(
        '{"action":"rename_tag","tag":"work","name":"job"}',
      );
      expect(action?.kind, AssistantActionKind.renameTag);
      expect(action?.tagName, 'work');
      expect(action?.text, 'job');
      // Renaming a tag to itself is not a change, and renaming it to nothing
      // is a tag nobody can see.
      expect(
        parseAssistantAction(
          '{"action":"rename_tag","tag":"work","name":"Work"}',
        ),
        isNull,
      );
      expect(
        parseAssistantAction('{"action":"rename_tag","tag":"work"}'),
        isNull,
      );
    });

    test('a tag colour must be one the app can paint', () {
      expect(
        parseAssistantAction(
          '{"action":"tag_color","tag":"work","color":"1d4ed8"}',
        )?.text,
        '#1D4ED8',
        reason: 'the missing hash is a thing models do, not a bad colour',
      );
      expect(
        parseAssistantAction(
          '{"action":"tag_color","tag":"work","color":"default"}',
        )?.text,
        isNull,
        reason: 'clearing it back to the shipped colour',
      );
      // "blue" stored in that slot is a tag that renders as no colour at all
      // with nothing on screen to say why.
      for (final bad in ['blue', '#12', '#GGGGGG']) {
        expect(
          parseAssistantAction(
            '{"action":"tag_color","tag":"work","color":"$bad"}',
          ),
          isNull,
          reason: '$bad is not a colour this app can store',
        );
      }
    });

    test('the settings list grew and its boundary did not move', () {
      // Everything on the list passes the same three tests: changed by hand
      // from a settings screen, visible the moment it changes, reversible in
      // one tap. These are the ones that do not.
      for (final key in [
        'api_key',
        'sync_url',
        'ai.key.openai',
        'retention',
        'app_lock',
        'app_lock_timing',
        'ai_provider',
        'entitlement',
      ]) {
        expect(
          parseAssistantAction('{"action":"setting","key":"$key","value":"x"}'),
          isNull,
          reason: '$key is not the assistant\'s to change',
        );
      }
      // And a few that are.
      for (final key in ['text_size', 'daily_nudge', 'palette', 'show_tags']) {
        expect(
          parseAssistantAction(
            '{"action":"setting","key":"$key","value":"x"}',
          )?.settingKey,
          key,
        );
      }
    });

    test('settings that left the settings screen left the list too', () {
      // Background patterns were replaced by whole-app palettes and Comfort
      // Mode was hidden. Offered to the model, the first reported a change
      // that showed nothing and the second turned on something with no
      // switch left to turn it off.
      for (final key in ['background', 'comfort_mode']) {
        expect(
          parseAssistantAction(
            '{"action":"setting","key":"$key","value":"on"}',
          ),
          isNull,
          reason: '$key has no control a person can reach',
        );
      }
    });

    test('an accent is normalised before it is offered for confirmation', () {
      // Passed through raw, a colour without its `#` was confirmed by the user
      // and then silently rejected by the check that applies it.
      String? accent(String value) => parseAssistantAction(
        '{"action":"setting","key":"accent","value":"$value"}',
      )?.settingValue;
      expect(accent('1d4ed8'), '#1D4ED8');
      expect(accent('#1d4ed8'), '#1D4ED8');
      expect(accent('default'), 'default');
      expect(accent('blue'), isNull);
    });

    test('a recurring item needs to say how often', () {
      // "Every what?" has no sensible guess, and a wrong one is an insurance
      // renewal quietly set to every day.
      final yearly = parseAssistantAction(
        '{"action":"commitment","name":"car insurance","every":1,'
        '"unit":"years","at":"2027-03-14T09:00"}',
      );
      expect(yearly?.kind, AssistantActionKind.commitment);
      expect(yearly?.commitmentName, 'car insurance');
      expect(yearly?.cadence, NexCadence.years);
      expect(yearly?.every, 1);
      expect(yearly?.at, DateTime(2027, 3, 14, 9));

      expect(
        parseAssistantAction('{"action":"commitment","name":"x","every":1}'),
        isNull,
        reason: 'no unit is not an action',
      );
      expect(
        parseAssistantAction(
          '{"action":"commitment","name":"x","unit":"fortnights"}',
        ),
        isNull,
      );
    });

    test('a recurring item may be edited without restating its date', () {
      // Saying "make it every three months" should not force the model to
      // repeat a due date it was never told.
      final action = parseAssistantAction(
        '{"action":"commitment","name":"rent","every":3,"unit":"months"}',
      );
      expect(action?.cadence, NexCadence.months);
      expect(action?.every, 3);
      expect(action?.at, isNull);
    });

    test('a date that cannot be read refuses the whole thing', () {
      expect(
        parseAssistantAction(
          '{"action":"commitment","name":"rent","unit":"months","at":"soon"}',
        ),
        isNull,
      );
    });

    test('done and gone name the item rather than carrying a date', () {
      // Ticking one off rolls it forward by itself — the app works out when,
      // and a date from the model here would be the model overriding
      // arithmetic it cannot see.
      final met = parseAssistantAction(
        '{"action":"commitment_met","name":"drink water"}',
      );
      expect(met?.kind, AssistantActionKind.commitmentMet);
      expect(met?.commitmentName, 'drink water');
      expect(met?.at, isNull);

      final gone = parseAssistantAction(
        '{"action":"commitment_delete","name":"gym membership"}',
      );
      expect(gone?.kind, AssistantActionKind.commitmentDelete);
      expect(gone?.commitmentName, 'gym membership');
    });

    test('singular and plural units are both accepted', () {
      // Models write both, and refusing one of them is a feature that works
      // half the time.
      for (final unit in ['hour', 'hours']) {
        expect(
          parseAssistantAction(
            '{"action":"commitment","name":"tablet","every":8,"unit":"$unit"}',
          )?.cadence,
          NexCadence.hours,
        );
      }
    });

    test('an untagged fence is quoted material, never an action (AI-06)', () {
      expect(
        parseAssistantActions(
          'Your note says:\n```\n{"action":"delete","id":"a"}\n```',
        ),
        isEmpty,
      );
      // A tagged block still acts, and a bare object outside any fence too.
      expect(
        parseAssistantActions('```nex\n{"action":"delete","id":"a"}\n```'),
        hasLength(1),
      );
      expect(
        parseAssistantActions('Sure: {"action":"delete","id":"a"}'),
        hasLength(1),
      );
    });

    test('"done" sets the direction of a tick (AI-02)', () {
      final action = parseAssistantActions(
        '```nex\n{"action":"check","id":"a","index":0,"done":false}\n```',
      ).single;
      expect(action.flag, isFalse);
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

    test('an acting assistant is told what day it is', () {
      // Load-bearing exactly once `remind` existed. "Friday at nine" cannot
      // be turned into a date by something that does not know today's, and a
      // model with no clock does not refuse — it picks a date out of its
      // training data and sets an alarm for a day in the past.
      final prompt = adapter().chatSystemPrompt(
        AiChatOptions(canAct: true, now: DateTime(2026, 3, 12, 14, 5)),
      );
      expect(prompt, contains('2026-03-12T14:05'));
      // The weekday too: it is half of what people say, and deriving it from
      // the date is arithmetic no model should have to be right about.
      expect(prompt, contains('Thursday'));
      expect(prompt, contains('must be in the future'));
    });

    test('the clock is only there when it can be used', () {
      // A chat that cannot act cannot set a reminder, so the date is one
      // more line of context spent on nothing.
      expect(
        adapter().chatSystemPrompt(
          AiChatOptions(now: DateTime(2026, 3, 12, 14, 5)),
        ),
        isNot(contains('2026-03-12')),
      );
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

    testWidgets('retry keeps the question once and preserves a new draft', (
      tester,
    ) async {
      final sent = <String>[];
      await openSheet(
        tester,
        client: MockClient((request) async {
          sent.add(request.body);
          return sent.length == 1
              ? http.Response('{}', 503)
              : http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'message': {'content': 'Recovered answer'},
                      },
                    ],
                  }),
                  200,
                );
        }),
      );
      final field = find.descendant(
        of: find.byType(AiChatSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'original question');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.text('Recovered answer'), findsNothing);
      await tester.enterText(field, 'new draft');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(2));
      final messages = (jsonDecode(sent.last) as Map)['messages'] as List;
      expect(
        messages.where((m) => m['content'] == 'original question'),
        hasLength(1),
      );
      expect(tester.widget<TextField>(field).controller!.text, 'new draft');
      expect(find.text('Recovered answer'), findsOneWidget);
    });

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

    testWidgets('an answer names the notes it used, as chips that open them', (
      tester,
    ) async {
      final note = (await services.captureText('the boiler code is 4471'))!;
      await openSheet(
        tester,
        client: replying('The code is 4471.\nSources: [${note.id}]'),
      );
      await tester.enterText(find.byType(TextField).last, 'boiler code?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // The marker line is for the app: the reader sees the answer and the
      // note, never the id.
      expect(find.text('The code is 4471.'), findsOneWidget);
      expect(find.textContaining(note.id), findsNothing);
      final chip = find.widgetWithText(ActionChip, 'the boiler code is 4471');
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);
    });

    testWidgets('the notes matching a question reach the model (W2.4)', (
      tester,
    ) async {
      // Nothing volunteered: the only way the model can know about this note
      // is the search the question itself runs.
      await preferences.setAiNotesContextCount(0);
      final note = (await services.captureText('the boiler code is 4471'))!;
      await services.captureText('buy milk');
      final bodies = <String>[];
      await openSheet(
        tester,
        client: MockClient((request) async {
          bodies.add(request.body);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'It is 4471.'},
                  },
                ],
              }),
            ),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      await tester.enterText(find.byType(TextField).last, 'boiler code');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(bodies, isNotEmpty);
      expect(bodies.last, contains(note.id));
      expect(bodies.last, isNot(contains('buy milk')));
    });

    testWidgets('an invented id makes no chip', (tester) async {
      await openSheet(
        tester,
        client: replying(
          'Nothing about that.\nSources: [01890000-0000-7000-8000-000000000000]',
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'anything?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.text('Nothing about that.'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('an answer from general knowledge says so', (tester) async {
      await preferences.setAiNotesOnly(false);
      await openSheet(
        tester,
        client: replying('[general] Paris is the capital of France.'),
      );
      await tester.enterText(find.byType(TextField).last, 'capital?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.text('Paris is the capital of France.'), findsOneWidget);
      expect(
        find.text('From general knowledge, not your notes'),
        findsOneWidget,
      );
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

    Future<void> ask(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).last, text);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
    }

    testWidgets('a delete names the note it deletes (SEC-02)', (tester) async {
      final note = (await services.captureText('the cooler is broken'))!;
      await tester.pumpAndSettle();
      await openSheet(
        tester,
        client: replying('```nex\n{"action":"delete","id":"${note.id}"}\n```'),
      );
      await ask(tester, 'delete the cooler note');

      expect(find.textContaining('“the cooler is broken”'), findsOneWidget);
    });

    testWidgets('"untick" unticks, under a card that says so (AI-02)', (
      tester,
    ) async {
      final list = (await services.captureChecklist(const [
        ChecklistItem(text: 'milk', done: true),
        ChecklistItem(text: 'eggs', done: false),
      ]))!;
      await tester.pumpAndSettle();
      await openSheet(
        tester,
        client: replying(
          '```nex\n{"action":"check","id":"${list.id}","index":0,'
          '"done":false}\n```',
        ),
      );
      await ask(tester, 'untick the milk');
      expect(find.text('Untick this item?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();
      expect(
        parseChecklist((await services.getById(list.id))!.content).first.done,
        isFalse,
      );

      // Asked again, it stays unticked rather than flipping back.
      await ask(tester, 'untick the milk');
      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();
      expect(
        parseChecklist((await services.getById(list.id))!.content).first.done,
        isFalse,
      );
    });

    testWidgets('a reminder already in the past is not set, and says so '
        '(AI-03)', (tester) async {
      final note = (await services.captureText('take the pills'))!;
      await tester.pumpAndSettle();
      final gone = DateTime.now().subtract(const Duration(days: 1));
      final at =
          '${gone.year}-${gone.month.toString().padLeft(2, '0')}-'
          '${gone.day.toString().padLeft(2, '0')}T09:00';
      await openSheet(
        tester,
        client: replying(
          '```nex\n{"action":"remind","id":"${note.id}","at":"$at"}\n```',
        ),
      );
      await ask(tester, 'remind me about the pills');
      expect(find.textContaining('this time has passed'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();

      expect((await services.getById(note.id))!.dueAt, isNull);
      expect(
        find.textContaining('That time has already passed'),
        findsOneWidget,
      );
    });

    testWidgets('a search the question did not ask for waits for the button '
        '(AI-05)', (tester) async {
      await services.captureText('bank pin is in the drawer');
      await tester.pumpAndSettle();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final content = calls == 1
            ? '```nex\n{"action":"search","query":"bank"}\n```'
            : 'Done looking.';
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
      await openSheet(tester, client: client);
      await ask(tester, 'what did I write about the cooler?');

      // Nothing was searched or sent on the model's say-so.
      expect(calls, 1);
      expect(find.text('Search your notes for this?'), findsOneWidget);
      expect(find.textContaining('“bank”'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });

    testWidgets('a note and its reminder, in one request', (tester) async {
      final when = DateTime.now().add(const Duration(days: 2));
      final at =
          '${when.year}-${when.month.toString().padLeft(2, '0')}-'
          '${when.day.toString().padLeft(2, '0')}T09:00';
      await openSheet(
        tester,
        client: replying(
          '```nex\n{"action":"create","text":"See the doctor","at":"$at"}\n```',
        ),
      );
      await tester.enterText(
        find.byType(TextField).last,
        'remind me to see the doctor at nine',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();

      final notes = await services.timeline(limit: 10);
      final made = notes.singleWhere((n) => n.content == 'See the doctor');
      expect(
        made.dueAt?.toLocal(),
        DateTime(when.year, when.month, when.day, 9),
      );
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

    /// Opens the assistant with [replies] as the model's answers, in turn,
    /// sends [question], and returns every request body sent.
    Future<List<String>> converse(
      WidgetTester tester,
      List<String> replies,
      String question,
    ) async {
      final sent = <String>[];
      var call = 0;
      final client = MockClient((request) async {
        sent.add(request.body);
        final content = replies[call.clamp(0, replies.length - 1)];
        call++;
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
      await tester.enterText(find.byType(TextField).last, question);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('"summarise my work notes": every note with the tag comes '
        'back to the model', (tester) async {
      final work = await services.captureText('quarterly report due friday');
      await services.captureText('buy oat milk');
      await services.addTag(noteId: work!.id, name: 'work');
      await tester.pumpAndSettle();

      final sent = await converse(tester, [
        '```nex\n{"action":"search","tag":"work"}\n```',
        'One work note: the quarterly report is due Friday.',
      ], 'summarise my work notes');

      expect(sent, hasLength(2));
      final findings = sent.last.substring(sent.last.indexOf('Notes with tag'));
      expect(findings, contains('quarterly report'));
      expect(findings, isNot(contains('oat milk')));
      expect(find.widgetWithText(FilledButton, 'Do it'), findsNothing);
    });

    testWidgets('"what is in the Trip thread": the thread list, then its '
        'notes', (tester) async {
      final ticket = await services.captureText('train to Tabriz at 7');
      await services.createThread('Trip', noteIds: [ticket!.id]);
      await tester.pumpAndSettle();

      final sent = await converse(tester, [
        '```nex\n{"action":"threads"}\n```',
        '```nex\n{"action":"search","thread":"Trip"}\n```',
        "The Trip thread has your 7 o'clock train to Tabriz.",
      ], 'what is in my trip thread?');

      expect(sent, hasLength(3));
      expect(sent[1], contains('Trip (1 notes)'));
      expect(sent[2], contains('train to Tabriz'));
    });

    testWidgets('several notes tagged, and gathered into a new thread, from '
        'one confirmation', (tester) async {
      final a = await services.captureText('tiles for the kitchen');
      final b = await services.captureText('kitchen tap quote');
      await tester.pumpAndSettle();

      await converse(tester, [
        '```nex\n{"action":"tag","ids":["${a!.id}","${b!.id}"],'
            '"add":["home"]}\n```\n'
            '```nex\n{"action":"thread","ids":["${a.id}","${b.id}"],'
            '"name":"Kitchen"}\n```',
      ], 'tag the kitchen notes as home and put them in a thread');

      // Nothing has happened until the button is pressed.
      expect(await services.threads(), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Do it'));
      await tester.pumpAndSettle();

      for (final id in [a.id, b.id]) {
        final note = await services.getById(id);
        expect(note!.tags.map((t) => t.name), contains('home'));
      }
      final threads = await services.threads();
      expect(threads.single.name, 'Kitchen');
      expect(
        (await services.threadNotes(threads.single.id)).map((n) => n.id),
        unorderedEquals([a.id, b.id]),
      );
    });
  });
}
