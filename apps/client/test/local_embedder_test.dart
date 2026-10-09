import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/local_embedder.dart';
import 'package:nex_client/platform/model_store.dart';
import 'package:nex_client/platform/nex_services.dart';

/// The Dart half of the on-device search model. The native half
/// (NexEmbedder.kt) is LiteRT-LM's and only runs on a phone; what is tested
/// here is everything said to it and read back from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nex/embedder-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('what the model is asked', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return [
          Float32List.fromList([0.5, 0.25, 0.25]),
        ];
      });
    });

    test('a note goes in as a document, with the model path', () async {
      final embedder = NexLocalEmbedder(
        '/models/eg2.litertlm',
        channel: channel,
      );
      final vector = await embedder.embedDocument('dentist on Monday');

      expect(calls.single.method, 'embed');
      expect(calls.single.arguments, {
        'modelPath': '/models/eg2.litertlm',
        'texts': ['title: none | text: dentist on Monday'],
      });
      expect(vector, [0.5, 0.25, 0.25]);
    });

    test('a search goes in as a query', () async {
      final embedder = NexLocalEmbedder('/m', channel: channel);
      await embedder.embedQuery('tooth doctor');

      expect((calls.single.arguments as Map)['texts'], [
        'task: search result | query: tooth doctor',
      ]);
    });

    test('a very long note is cut to what the model is given', () async {
      final embedder = NexLocalEmbedder('/m', channel: channel);
      await embedder.embedDocument('a' * (NexLocalEmbedder.maxChars + 500));

      final sent = ((calls.single.arguments as Map)['texts'] as List).single;
      expect(sent, 'title: none | text: ${'a' * NexLocalEmbedder.maxChars}');
    });

    test('the check proves the model answers', () async {
      await NexLocalEmbedder.check('/m', channel: channel);
      expect(calls.single.method, 'embed');
    });
  });

  group('what comes back', () {
    test('a Kotlin FloatArray and a plain list read the same', () {
      expect(NexLocalEmbedder.vectorOf(Float32List.fromList([1, 2])), [
        1.0,
        2.0,
      ]);
      expect(NexLocalEmbedder.vectorOf(<Object?>[1, 2.5]), [1.0, 2.5]);
    });

    test('a runtime error reaches the caller, so the note is retried', () {
      // An empty vector would mark the note as having nothing to embed —
      // permanently. A thrown error leaves it in the backlog.
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'embed', message: 'would not load');
      });
      expect(
        NexLocalEmbedder('/m', channel: channel).embedDocument('x'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a build without the runtime fails rather than answers', () {
      // Nothing registered on the channel at all.
      expect(
        NexLocalEmbedder('/m', channel: channel).embedQuery('x'),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('releasing in a build without the runtime is not an error', () async {
      await NexLocalEmbedder.release(channel: channel);
    });
  });

  group('which vector space the library is in', () {
    const openai = AiProviderConfig(provider: AiProvider.openai, apiKey: 'k');
    const anthropic = AiProviderConfig(
      provider: AiProvider.anthropic,
      apiKey: 'k',
    );

    test('the search model wins, whatever the provider', () {
      expect(
        nexEmbeddingSpaceFor(provider: openai, localSearch: true),
        NexLocalEmbedder.embeddingSpace,
      );
      expect(
        nexEmbeddingSpaceFor(provider: null, localSearch: true),
        NexLocalEmbedder.embeddingSpace,
      );
    });

    test('without it, the provider that embeds', () {
      expect(
        nexEmbeddingSpaceFor(provider: openai, localSearch: false),
        openai.embeddingSpace,
      );
    });

    test('neither leaves the space alone — no vectors thrown away', () {
      // A provider without embeddings, or AI switched off, is not a new
      // space: treating it as one would empty the library's vectors every
      // time the switch was flipped.
      expect(
        nexEmbeddingSpaceFor(provider: anthropic, localSearch: false),
        isNull,
      );
      expect(
        nexEmbeddingSpaceFor(
          provider: const AiProviderConfig(),
          localSearch: false,
        ),
        isNull,
      );
    });
  });

  test('only the model store\'s own file is taken as the search model '
      '(SEC-03)', () {
    // The path travels in a backup's settings: a crafted one must not point
    // the native embedder at an arbitrary, never-verified file.
    const root = '/data/user/0/com.sanyzrn.nex/files/models';
    final model = NexModels.search.single;
    expect(
      NexServices.isSearchModelFile(
        '$root/${model.id}/${model.filename}',
        root: root,
      ),
      isTrue,
    );
    for (final elsewhere in [
      '/sdcard/Download/${model.filename}',
      '$root/../../evil/${model.filename}',
      '$root/${model.id}/other.bin',
    ]) {
      expect(
        NexServices.isSearchModelFile(elsewhere, root: root),
        isFalse,
        reason: elsewhere,
      );
    }
  });
}
