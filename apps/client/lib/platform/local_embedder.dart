import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

/// The on-device search model, EmbeddingGemma 2, behind `nex/embedder`.
///
/// The native side is LiteRT-LM's `EmbeddingEngine` (NexEmbedder.kt), kept
/// loaded between calls. This class is what the database worker holds as
/// its [NoteEmbedder]; it runs in that worker's isolate, which is why the
/// worker is given the root isolate token at spawn.
///
/// A missing channel — a build or platform without the runtime — is an
/// error, not an empty vector: the note then stays in the backlog instead of
/// being marked as having nothing to embed.
class NexLocalEmbedder implements NoteEmbedder {
  NexLocalEmbedder(this.modelPath, {MethodChannel? channel})
    : _channel = channel ?? _shared;

  final String modelPath;
  final MethodChannel _channel;

  static const _shared = MethodChannel('nex/embedder');

  /// The vector space this model writes, for `setEmbeddingSpace`. Bumped
  /// with the model, never with the app: the same weights write the same
  /// vectors whichever version of Nex holds them.
  static const embeddingSpace = 'local|embeddinggemma-2-text-270m|v1';

  @override
  String get space => embeddingSpace;

  /// EmbeddingGemma's own prompts — the "Prompt instructions" of its model
  /// card, as Google's LiteRT-LM search demo applies them. A note and a
  /// search are told apart this way so that a short question lands near the
  /// long note that answers it, not near other short questions.
  @visibleForTesting
  static String documentPrompt(String text) =>
      'title: none | text: ${clip(text)}';

  @visibleForTesting
  static String queryPrompt(String text) =>
      'task: search result | query: ${clip(text)}';

  /// The most characters of one text the model is given.
  ///
  /// A bound, because a note can be a whole imported document: the engine's
  /// time grows with its length, and one note it cannot take would stop
  /// every note behind it, since a failed note is retried first. What a note
  /// is about is in its opening, which is also what a person scanning it
  /// reads.
  static const maxChars = 4000;

  @visibleForTesting
  static String clip(String text) =>
      text.length <= maxChars ? text : text.substring(0, maxChars);

  @override
  Future<List<double>> embedDocument(String text) => _one(documentPrompt(text));

  @override
  Future<List<double>> embedQuery(String text) => _one(queryPrompt(text));

  Future<List<double>> _one(String text) async {
    final reply = await _channel.invokeMethod<List<Object?>>('embed', {
      'modelPath': modelPath,
      'texts': [text],
    });
    if (reply == null || reply.isEmpty) {
      throw StateError('The search model returned no vector');
    }
    return vectorOf(reply.first);
  }

  /// A vector as the platform channel delivers it: a `Float32List` from a
  /// Kotlin `FloatArray`, or a plain list from anything else.
  @visibleForTesting
  static List<double> vectorOf(Object? raw) => switch (raw) {
    Float32List values => [for (final v in values) v.toDouble()],
    Float64List values => List<double>.of(values),
    List<Object?> values => [for (final v in values) (v! as num).toDouble()],
    _ => throw StateError('The search model returned ${raw.runtimeType}'),
  };

  /// Proves the model loads and answers, for the install screen's last step.
  /// Throws what the runtime said when it does not.
  static Future<void> check(String modelPath, {MethodChannel? channel}) async {
    final vector = await NexLocalEmbedder(
      modelPath,
      channel: channel,
    ).embedQuery('Nex');
    if (vector.isEmpty) {
      throw StateError('The search model returned an empty vector');
    }
  }

  /// Unloads the model, before its file is deleted. Nothing to do when none
  /// is loaded, or when this build has no runtime at all.
  static Future<void> release({MethodChannel? channel}) async {
    try {
      await (channel ?? _shared).invokeMethod<void>('release');
    } on MissingPluginException {
      // No runtime in this build, so nothing was ever loaded.
    }
  }
}

/// Which vector space the library should be in, or null to leave it as it
/// is.
///
/// The on-device search model wins whenever it is in use: that is what it
/// was installed for, and it is the only one that never sends a note
/// anywhere to be read. Otherwise the provider's, if it embeds at all. Null
/// when neither does — turning AI off, or a provider without embeddings,
/// must not count as a change of space, or switching off and on again would
/// throw every vector away for nothing.
String? nexEmbeddingSpaceFor({
  required AiProviderConfig? provider,
  required bool localSearch,
}) {
  if (localSearch) return NexLocalEmbedder.embeddingSpace;
  if (provider != null && provider.isUsable && provider.provider.embeds) {
    return provider.embeddingSpace;
  }
  return null;
}
