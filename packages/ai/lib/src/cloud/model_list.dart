part of 'ai_provider.dart';

/// The models a provider says this key can use, for picking one from a list
/// rather than typing an id from memory (2.1.8).
///
/// A typo in a model id was the most common way to a setup that connects
/// and then fails on every request, and the ids change every few months.
/// The provider's own list is the one that is never out of date.
extension AiModelList on CloudAIAdapter {
  /// Model ids, sorted, or an [AiUnavailableException] saying why not.
  ///
  /// Narrowed to what can answer a chat where the provider says so (Gemini
  /// lists what each model is for) or where the id plainly says otherwise
  /// (OpenAI's speech, image and embedding models). A Custom gateway's names
  /// are its own business and are all kept.
  Future<List<String>> listModels() => NexDisclosureLog.about(() async {
    final uri = switch (config.provider) {
      AiProvider.none => null,
      AiProvider.gemini => Uri.parse(
        '${config.resolvedBaseUrl}/v1beta/models?pageSize=1000',
      ),
      AiProvider.anthropic => Uri.parse(
        '${config.resolvedBaseUrl}/v1/models?limit=1000',
      ),
      AiProvider.custom => switch (config.customSibling('models')) {
        final String sibling => Uri.parse(sibling),
        null => null,
      },
      _ => Uri.parse('${config.resolvedBaseUrl}/v1/models'),
    };
    if (uri == null || config.apiKey.trim().isEmpty) {
      throw const AiUnavailableException();
    }
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    final body = CloudAIAdapter._bodyText(response);
    if (response.statusCode != 200) {
      throw AiUnavailableException(
        CloudAIAdapter._describe(
          response.statusCode,
          CloudAIAdapter._extractError(body),
        ),
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const AiUnavailableException();
    }
    if (decoded is! Map) throw const AiUnavailableException();
    final ids = <String>{};
    if (config.provider == AiProvider.gemini) {
      for (final model in (decoded['models'] as List?) ?? const []) {
        if (model is! Map || model['name'] is! String) continue;
        final methods = model['supportedGenerationMethods'];
        if (methods is List && !methods.contains('generateContent')) continue;
        final id = (model['name'] as String).replaceFirst('models/', '');
        if (RegExp(r'tts|embedding|imagen|veo|aqa').hasMatch(id)) continue;
        ids.add(id);
      }
    } else {
      for (final model in (decoded['data'] as List?) ?? const []) {
        if (model is! Map || model['id'] is! String) continue;
        final id = model['id'] as String;
        if (config.provider == AiProvider.openai &&
            RegExp(
              r'embedding|whisper|tts|dall-e|transcribe|moderation|'
              r'realtime|davinci|babbage|^sora|^gpt-image|-audio-|-search-',
            ).hasMatch(id)) {
          continue;
        }
        ids.add(id);
      }
    }
    return ids.toList()..sort();
  }, purpose: DisclosurePurpose.connectionTest);
}
