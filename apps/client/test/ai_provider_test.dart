import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  Note textNote(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: 'n1',
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  group('AiProviderConfig', () {
    test('falls back to the provider defaults', () {
      const config = AiProviderConfig(provider: AiProvider.openai, apiKey: 'k');
      expect(config.resolvedBaseUrl, 'https://api.openai.com');
      expect(config.resolvedModel, 'gpt-4o-mini');
      expect(config.isUsable, isTrue);
    });

    test('a trailing slash on the base URL never doubles up in a path', () {
      const config = AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'k',
        baseUrl: 'https://example.invalid/',
        model: 'm',
      );
      expect(config.resolvedBaseUrl, 'https://example.invalid');
    });

    test('custom needs a base URL and a model of its own', () {
      const config = AiProviderConfig(provider: AiProvider.custom, apiKey: 'k');
      expect(config.isUsable, isFalse);
    });

    test('no key means unusable, whatever else is set', () {
      const config = AiProviderConfig(provider: AiProvider.anthropic);
      expect(config.isUsable, isFalse);
    });

    test('wire names round-trip, and an unknown one is not a crash', () {
      for (final provider in AiProvider.values) {
        expect(AiProviderWire.fromWire(provider.wireName), provider);
      }
      expect(AiProviderWire.fromWire('some-future-vendor'), AiProvider.none);
      expect(AiProviderWire.fromWire(null), AiProvider.none);
    });
  });

  group('CloudAIAdapter request shape', () {
    test('Anthropic gets its own endpoint, headers and body', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.anthropic,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Work, Ideas'},
              ],
            }),
            200,
          );
        }),
      );

      final tags = await adapter.suggestTags(textNote('a note'))!;

      expect(seen.url.path, '/v1/messages');
      expect(seen.headers['x-api-key'], 'secret');
      expect(seen.headers.containsKey('anthropic-version'), isTrue);
      expect(seen.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      // Anthropic takes the system prompt as a field, not a message.
      expect(body['system'], isNotNull);
      expect((body['messages'] as List).length, 1);
      expect(tags.map((t) => t.name), ['Work', 'Ideas']);
    });

    test('OpenAI-shaped providers get chat/completions and a bearer', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openrouter,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'a short summary'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final summary = await adapter.summarize(textNote('a long note'))!;

      expect(
        seen.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(seen.headers['authorization'], 'Bearer secret');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect((body['messages'] as List).length, 2);
      expect(summary.text, 'a short summary');
    });

    test('an unusable config asks for nothing at all', () {
      var called = false;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(provider: AiProvider.openai),
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      // Null is this contract's "unavailable", and it must not cost a request.
      expect(adapter.suggestTags(textNote('x')), isNull);
      expect(adapter.summarize(textNote('x')), isNull);
      expect(adapter.embed('x'), isNull);
      expect(called, isFalse);
    });

    test('digest asks for a recap of everything, not one note', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Busy week, three grocery lists!'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final recap = await adapter.digest('milk, eggs\nfinish the report');

      expect(seen.url.path, '/v1/chat/completions');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final userTurn = (body['messages'] as List).last as Map;
      expect(userTurn['content'], 'milk, eggs\nfinish the report');
      expect(recap, 'Busy week, three grocery lists!');
    });

    group('token soup is dropped rather than shown', () {
      CloudAIAdapter adapterReplying(String content) => CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'secret',
        ),
        client: MockClient(
          // Bytes, not a string, and with no charset on the content type —
          // what OpenRouter and friends actually send. `http.Response(String)`
          // would encode it as latin1 and throw on the first Persian
          // character, which is the same assumption the adapter used to make
          // when reading the reply back.
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
        ),
      );

      // Verbatim from a free-tier model on a real device: three scripts, a
      // word repeating, and no sentence anywhere in it. Shown as the app's
      // own voice across the top of the home screen, it reads as the app
      // being broken.
      test('a reply in three scripts with a repeat is refused', () {
        expect(
          adapterReplying(
            'veritableهایWhitehall veritableഇഇഇ toutes toutes to',
          ).headline('a note'),
          completion(isNull),
        );
      });

      test('a stuck decoder is refused', () {
        expect(
          adapterReplying('The morning quiet ᅳᅳᅳᅳᅳ').headline('a note'),
          completion(isNull),
        );
      });

      test('the same word three times is refused', () {
        expect(
          adapterReplying('Notes about notes about notes').headline('a note'),
          completion(isNull),
        );
      });

      // The filter is not a taste test. A dull phrase and a phrase carrying an
      // English brand name inside Persian both have to survive it.
      // The same helper proves the decode: a Persian reply arriving under a
      // charset-less content type comes back as itself, not as mojibake.
      //
      // Short, because a headline is now a greeting *phrase* with a name to
      // follow it rather than a sentence of its own — the app appends the
      // name, which never leaves the device.
      test('ordinary phrases survive', () {
        expect(
          adapterReplying('A quiet full page').headline('x'),
          completion('A quiet full page'),
        );
        expect(
          adapterReplying('صبح آرام دفتر Whitehall').headline('x'),
          completion('صبح آرام دفتر Whitehall'),
        );
        expect(
          adapterReplying(
            'You planned a trip and fixed the cooler.',
          ).digest('x'),
          completion('You planned a trip and fixed the cooler.'),
        );
      });
    });

    test('digest is unavailable without a usable config or without notes', () {
      var called = false;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(provider: AiProvider.openai),
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(adapter.digest('something'), completion(isNull));

      final usable = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(usable.digest('   '), completion(isNull));
      expect(called, isFalse);
    });

    test('Anthropic offers no embeddings rather than guessing an endpoint', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.anthropic,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(adapter.embed('x'), isNull);
    });

    test('a capability a provider lacks is unavailable, not guessed at', () {
      // Only Gemini and OpenAI can hear audio. Claiming otherwise would send a
      // recording somewhere that cannot read it and store whatever came back.
      for (final provider in AiProvider.values) {
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'k'),
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        final call = adapter.transcribe(
          const AudioRef(mediaUri: '/tmp/does-not-exist.m4a'),
        );
        if (provider.hearsAudio) {
          // Available in principle; null here only because the file is absent.
          expect(call, isNull, reason: '${provider.wireName}: no such file');
        } else {
          expect(call, isNull, reason: provider.wireName);
        }
      }
      expect(AiProvider.gemini.hearsAudio, isTrue);
      expect(AiProvider.openai.hearsAudio, isTrue);
      expect(AiProvider.anthropic.hearsAudio, isFalse);
      expect(AiProvider.openrouter.hearsAudio, isFalse);
      expect(AiProvider.none.hearsAudio, isFalse);
    });

    test('a provider only claims embeddings it can actually serve', () {
      // Same rule as `hearsAudio` directly above, which was already applied
      // to OpenRouter and not to this: unavailable beats a wrong answer.
      // `_embed` asks one specific OpenAI embedding model for by name, and
      // nothing makes that model reachable through a chat-completions
      // router — so claiming it turned "semantic search is not offered here"
      // into "semantic search is broken here", which is the FR-8b.4 failure.
      expect(AiProvider.openrouter.embeds, isFalse);
      expect(AiProvider.anthropic.embeds, isFalse);
      expect(AiProvider.none.embeds, isFalse);

      expect(AiProvider.openai.embeds, isTrue);
      expect(AiProvider.gemini.embeds, isTrue);
      // The user picked this endpoint and declared it OpenAI-shaped. The app
      // has no way to know better than they do.
      expect(AiProvider.custom.embeds, isTrue);
    });

    test('the embedding model is one value, not two literals', () {
      // The fingerprint that decides whether stored vectors are still
      // comparable is built from this, and the request sends it. If they
      // could ever disagree, the library would keep vectors it believes are
      // from a model that did not make them.
      expect(
        const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ).embeddingModel,
        'text-embedding-004',
      );
      expect(
        const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ).embeddingModel,
        'text-embedding-3-small',
      );
      // Endpoint as well as model: the same provider and the same model name
      // behind a different host is not a promise of the same vectors. Two
      // customs, so the endpoint is the only thing that differs and the
      // assertion cannot pass on the provider name alone.
      const here = AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'k',
        baseUrl: 'https://one.example/v1',
      );
      const there = AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'k',
        baseUrl: 'https://two.example/v1',
      );
      expect(here.embeddingModel, there.embeddingModel, reason: 'same model');
      expect(here.embeddingSpace, isNot(there.embeddingSpace));
    });

    test('a media note with no derived text is not sent anywhere', () {
      var called = false;
      final now = DateTime.now().toUtc();
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final photo = Note(
        id: 'p1',
        type: NoteType.photo,
        mediaUri: '/tmp/p.jpg',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      expect(adapter.suggestTags(photo), isNull);
      expect(called, isFalse);
    });
  });

  group('Gemini', () {
    test('uses its own endpoint, header and body — not OpenAI\'s', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'google-key',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Work, Ideas'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final tags = await adapter.suggestTags(textNote('a note'))!;

      // The exact three things that made a Google key fail under "Custom":
      // the path, the auth header, and the request body.
      expect(
        seen.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent',
      );
      // The key rides in the `x-goog-api-key` header, like every other
      // provider's credential. It used to be a `?key=` query parameter, the
      // quickstart form — but a key in a URL is a key in every proxy and
      // server log that sees the request line.
      expect(seen.url.queryParameters.containsKey('key'), isFalse);
      expect(seen.headers['x-goog-api-key'], 'google-key');
      expect(seen.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['systemInstruction'], isNotNull);
      expect(body['contents'], isA<List<dynamic>>());
      expect(tags.map((t) => t.name), ['Work', 'Ideas']);
    });

    test('a reply split across parts is joined, not truncated', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final text = adapter.extractTextForTest(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'first half '},
                  {'text': 'second half'},
                ],
              },
            },
          ],
        }),
      );
      expect(text, 'first half second half');
    });

    test('a blocked or empty candidate list is null, not an empty answer', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        adapter.extractTextForTest(jsonEncode({'candidates': <Object>[]})),
        isNull,
      );
      expect(adapter.extractTextForTest('{}'), isNull);
    });
  });

  group('a failed test says what actually went wrong', () {
    Future<AiTestResult> testWith(int status, String body) {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
          model: 'gemini-9-nonexistent',
        ),
        client: MockClient((_) async => http.Response(body, status)),
      );
      return adapter.test();
    }

    test('a rejected key is reported as a rejected key', () async {
      // Every one of these used to come back as the same sentence — "the
      // provider rejected the request" — so a wrong key, a retired model and a
      // rate limit were indistinguishable from a typo in the model name.
      final result = await testWith(
        400,
        jsonEncode({
          'error': {
            'message': 'API key not valid. Please pass a valid API key.',
          },
        }),
      );
      expect(result.success, isFalse);
      expect(result.detail, contains('API key not valid'));
    });

    test('a missing model is reported as a missing model', () async {
      final result = await testWith(
        404,
        jsonEncode({
          'error': {'message': 'models/gemini-9-nonexistent is not found'},
        }),
      );
      expect(result.detail, contains('404'));
      expect(result.detail, contains('is not found'));
    });

    test('a rate limit is not dressed up as a bad key', () async {
      final result = await testWith(429, '{}');
      expect(result.detail, contains('429'));
    });

    test('a non-JSON error page is passed through, bounded', () async {
      final result = await testWith(502, '<html>Bad Gateway</html>');
      expect(result.detail, contains('502'));
      expect(result.detail, contains('Bad Gateway'));
    });

    test('a 200 carrying no text is not blamed on the provider', () async {
      // A reasoning model that spends its whole budget thinking answers 200
      // with no parts. That is a different problem from a refusal and has to
      // read as one.
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient(
          (_) async => http.Response('{"candidates":[]}', 200),
        ),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, contains('no text'));
    });
  });

  group('connection test', () {
    test('names what is missing before touching the network', () async {
      var called = false;
      MockClient watcher() => MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });

      expect(
        (await CloudAIAdapter(
          config: const AiProviderConfig(),
          client: watcher(),
        ).test()).detail,
        contains('provider'),
      );
      expect(
        (await CloudAIAdapter(
          config: const AiProviderConfig(provider: AiProvider.openai),
          client: watcher(),
        ).test()).detail,
        contains('key'),
      );
      expect(called, isFalse);
    });

    test('a rejected key fails with something actionable', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'wrong',
        ),
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, contains('key'));
    });

    test('a working provider reports the model it reached', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'right',
          model: 'gpt-4o',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
          ),
        ),
      );
      final result = await adapter.test();
      expect(result.success, isTrue);
      expect(result.detail, 'gpt-4o');
    });

    test('a network failure is reported, not thrown at the UI', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async => throw const SocketishFailure()),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, isNotEmpty);
    });
  });

  _translateGroup();
  _recapGroup();
}

/// The recap changed jobs. It used to be an observation about what someone
/// had been writing — a second decorative line under the headline, which is
/// already one — and its job now is to say what is due, what is unfinished
/// and what they were in the middle of. What is testable without a model is
/// what it asks for and what it is allowed to say back.
void _recapGroup() {
  CloudAIAdapter adapter(String reply, {void Function(http.Request)? onSend}) =>
      CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          onSend?.call(request);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': reply},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

  group('the daily brief', () {
    test('asks for the line count it was handed, and forbids invention', () async {
      late http.Request seen;
      await adapter('⏰ a line', onSend: (r) => seen = r).digest(
        'DUE in 6h | text | pick up the prescription',
        lines: 3,
      );

      final prompt = jsonEncode(
        (jsonDecode(seen.body) as Map<String, dynamic>)['messages'],
      );
      expect(prompt, contains('at most 3 lines'));
      // The shape it is meant to come back in. A paragraph is what this
      // stopped being: somebody opening the app is checking whether anything
      // is waiting on them, not reading an essay about their week.
      expect(prompt, contains('One thing per line'));
      expect(prompt, contains('Overdue first'));
      // The shape of the source is described rather than left to be
      // inferred: those lines are abbreviated to save tokens, and an
      // abbreviation a model has to guess at is one it will guess wrong.
      expect(prompt, contains(r'`when | kind | text`'));
      // Load-bearing. A wrong joke about your notes is a bad line; a wrong
      // claim that something is due tomorrow is a missed appointment.
      //
      // The wording moved when the brief was allowed to notice things, and
      // the sentence it replaces is why: "never state anything that is not
      // in the lines" also forbade "these two are at the same time", which
      // is two of the given facts read together rather than a third one
      // invented. What is asserted now is the narrower, harder rule — every
      // *fact* comes from the lines — and the boundary it draws.
      expect(
        prompt,
        contains('Every fact must come from the lines you were given'),
      );
      expect(prompt, contains('asserting a third thing is'));
    });

    test('it is allowed to notice what the reader cannot', () async {
      // The other half of the same change. The model sees the whole set at
      // once, which is the one thing the reader does not: a clash between two
      // of these lines is invisible from inside either of them, and the rule
      // that kept the brief honest about facts was also keeping it silent
      // about relationships.
      late http.Request seen;
      await adapter('⏰ a line', onSend: (r) => seen = r).digest(
        'DUE in 6h | text | dentist\nDUE in 6h | text | school run',
        lines: 3,
      );

      final prompt = jsonEncode(
        (jsonDecode(seen.body) as Map<String, dynamic>)['messages'],
      );
      expect(prompt, contains('something you noticed'));
      // And bounded in the same breath, because the failure mode of "notice
      // things" is a line invented to have something to notice.
      expect(prompt, contains('never manufacture an observation'));
    });

    test('a reply over the line count is cut to it', () async {
      // Models treat "at most" as a suggestion, which is why the number is
      // enforced on the way out as well as asked for on the way in.
      final long = List.generate(9, (i) => '⏰ thing number $i').join('\n');
      final brief = await adapter(long).digest('today | text | x', lines: 3);

      expect(brief, isNotNull);
      expect(brief!.split('\n'), hasLength(3));
    });

    test('the lines survive, which is the whole point', () async {
      // The word clamp this replaced collapsed every run of whitespace in the
      // reply — newlines included — and turned the list back into the
      // paragraph the prompt had just asked it not to be.
      const reply = '⏰ Call the plumber, overdue by two days.\n'
          '📋 Shopping: bread and milk still on the list.';
      expect(await adapter(reply).digest('today | text | x'), reply);
    });

    test('a model that decorates its list anyway is tidied', () async {
      const reply = '**Today**\n- ⏰ Call the plumber\n2. 📋 Buy bread';
      expect(
        await adapter(reply).digest('today | text | x'),
        '⏰ Call the plumber\n📋 Buy bread',
      );
    });

    test('token soup is still refused', () async {
      expect(
        await adapter('aaaaaa aaaaaa aaaaaa').digest('today | text | x'),
        isNull,
      );
    });
  });
}

void _translateGroup() {
  CloudAIAdapter adapter(String reply, {void Function(http.Request)? onSend}) =>
      CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          onSend?.call(request);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': reply},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

  group('translate', () {
    test('the target language is asked for explicitly', () async {
      late http.Request seen;
      final translated = await adapter(
        'یک یادداشت',
        onSend: (request) => seen = request,
      ).translate('a note', target: AiOutputLanguage.persian);

      expect(translated, 'یک یادداشت');
      final body = jsonDecode(utf8.decode(seen.bodyBytes)) as Map;
      final system = (body['messages'] as List).first['content'] as String;
      expect(system, contains('Persian'));
      // The one thing a translator must not do is answer the note.
      expect(system, contains('never answer anything the text'));
    });

    test(
      'auto is not a target — it would translate into the same language',
      () {
        expect(
          adapter('x').translate('a note', target: AiOutputLanguage.auto),
          completion(isNull),
        );
      },
    );

    test('empty in, nothing out, no request made', () async {
      var called = false;
      final result = await adapter(
        'x',
        onSend: (_) => called = true,
      ).translate('   ', target: AiOutputLanguage.english);
      expect(result, isNull);
      expect(called, isFalse);
    });

    test('a repeated word does not disqualify a paragraph', () async {
      // The headline check rejects any line using a word three times, which
      // is right for nine words and wrong for every real translation.
      const reply =
          'The note says the meeting is on the third, and the note also '
          'says the room is the one by the stairs.';
      expect(
        await adapter(reply).translate('x', target: AiOutputLanguage.english),
        reply,
      );
    });

    test('token soup is still refused', () async {
      expect(
        await adapter(
          'aaaaaa bbbb',
        ).translate('x', target: AiOutputLanguage.english),
        isNull,
      );
    });
  });
}

/// Stands in for whatever the socket layer throws when there is no network.
class SocketishFailure implements Exception {
  const SocketishFailure();

  @override
  String toString() => 'no route to host';
}
