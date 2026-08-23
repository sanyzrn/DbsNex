import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_core/nex_core.dart';

/// Stands in for a downloaded model, and records what it was asked.
class _FakeLocalModel implements ChatAdapter {
  _FakeLocalModel({this.available = true, this.reply = 'a local answer'});

  @override
  final bool available;

  final String reply;
  final calls = <List<ChatMessage>>[];

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    if (!available) return null;
    calls.add(history);
    return Future.value(ChatResponse(content: reply));
  }
}

/// Fails the test if anything reaches the network. Every case here has no
/// provider configured, so a request leaving the device is the bug.
http.Client get _noNetwork =>
    MockClient((request) async => fail('unexpected request to ${request.url}'));

void main() {
  const noProvider = AiProviderConfig(provider: AiProvider.none, apiKey: '');
  const withProvider = AiProviderConfig(
    provider: AiProvider.openai,
    apiKey: 'k',
  );

  group('with a model on the phone and no provider', () {
    // This group exists because the feature shipped once with the model
    // downloaded, loaded, and connected to nothing: every text feature was
    // gated on a cloud key, so two gigabytes bought an unchanged app.
    late _FakeLocalModel local;
    late CloudAIAdapter adapter;

    setUp(() {
      local = _FakeLocalModel();
      adapter = CloudAIAdapter(
        config: noProvider,
        client: _noNetwork,
        localModel: local,
      );
    });

    test('the app reports it can answer', () {
      expect(adapter.canAnswerText, isTrue);
      expect(
        aiTextAvailableWith(noProvider),
        isFalse,
        reason: 'the top-level helper reads the real binding, not this fake',
      );
    });

    test('the assistant answers from the model', () async {
      final reply = await adapter.chat(const [
        ChatMessage(role: ChatRole.user, content: 'hello'),
      ]);
      expect(reply, 'a local answer');
    });

    test('the assistant is given its instructions as a system turn', () async {
      await adapter.chat(const [
        ChatMessage(role: ChatRole.user, content: 'hello'),
      ]);
      final sent = local.calls.single;
      // Not glued onto the front of what the user typed: the adapter maps
      // this role onto the runtime's own system-instruction slot.
      expect(sent.first.role, ChatRole.system);
      expect(sent.first.content, contains('Nex'));
      expect(sent.last.content, 'hello');
    });

    test('the daily recap and the headline come from the model', () async {
      expect(await adapter.digest('a note about tuesday'), isNotNull);
      expect(await adapter.headline('a note about tuesday'), isNotNull);
    });

    test('translation goes through it too', () async {
      final out = await adapter.translate(
        'salaam',
        target: AiOutputLanguage.english,
      );
      expect(out, isNotNull);
    });

    test(
      'hearing and seeing stay unavailable, rather than being faked',
      () async {
        // A text model asked to transcribe would invent a plausible transcript,
        // which is worse than no transcript: nothing marks it as invented.
        expect(adapter.transcribe(const AudioRef(mediaUri: 'a.m4a')), isNull);
        expect(adapter.ocr(const ImageRef(mediaUri: 'a.jpg')), isNull);
        expect(adapter.embed('anything'), isNull);
        expect(local.calls, isEmpty);
      },
    );
  });

  test('no model and no provider still answers nothing', () async {
    final adapter = CloudAIAdapter(
      config: noProvider,
      client: _noNetwork,
      localModel: _FakeLocalModel(available: false),
    );
    expect(adapter.canAnswerText, isFalse);
    expect(
      await adapter.chat(const [
        ChatMessage(role: ChatRole.user, content: 'hello'),
      ]),
      isNull,
    );
    expect(await adapter.digest('something'), isNull);
  });

  test(
    'a configured provider is still preferred over the local model',
    () async {
      // The model is a fallback for having no provider, not an override of one.
      // Someone who pays for Claude and also downloaded the model should get
      // Claude.
      final local = _FakeLocalModel();
      var requests = 0;
      final adapter = CloudAIAdapter(
        config: withProvider,
        client: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncodedChoice('the cloud answer'),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
        localModel: local,
      );

      final reply = await adapter.chat(const [
        ChatMessage(role: ChatRole.user, content: 'hello'),
      ]);

      expect(reply, 'the cloud answer');
      expect(requests, 1);
      expect(local.calls, isEmpty);
    },
  );
}

/// One OpenAI-shaped completion.
String jsonEncodedChoice(String content) =>
    '{"choices":[{"message":{"content":${_quote(content)}}}]}';

String _quote(String value) => '"${value.replaceAll('"', r'\"')}"';
