import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nex_core/nex_core.dart';

/// The cloud services Nex can talk to.
///
/// Three of the four speak the OpenAI chat-completions shape, so they differ
/// only in host, auth header and default model. Anthropic's Messages API is a
/// different shape and gets its own branch.
enum AiProvider { none, anthropic, openai, openrouter, custom }

extension AiProviderWire on AiProvider {
  String get wireName => switch (this) {
        AiProvider.none => 'none',
        AiProvider.anthropic => 'anthropic',
        AiProvider.openai => 'openai',
        AiProvider.openrouter => 'openrouter',
        AiProvider.custom => 'custom',
      };

  String get label => switch (this) {
        AiProvider.none => 'On-device only',
        AiProvider.anthropic => 'Anthropic',
        AiProvider.openai => 'OpenAI',
        AiProvider.openrouter => 'OpenRouter',
        AiProvider.custom => 'Custom',
      };

  /// The base URL when the user has not supplied one.
  String get defaultBaseUrl => switch (this) {
        AiProvider.none => '',
        AiProvider.anthropic => 'https://api.anthropic.com',
        AiProvider.openai => 'https://api.openai.com',
        AiProvider.openrouter => 'https://openrouter.ai/api',
        AiProvider.custom => '',
      };

  String get defaultModel => switch (this) {
        AiProvider.none => '',
        AiProvider.anthropic => 'claude-sonnet-4-5',
        AiProvider.openai => 'gpt-4o-mini',
        AiProvider.openrouter => 'openai/gpt-4o-mini',
        AiProvider.custom => '',
      };

  /// Whether the request/response shape is OpenAI's rather than Anthropic's.
  bool get isOpenAiShaped =>
      this == AiProvider.openai ||
      this == AiProvider.openrouter ||
      this == AiProvider.custom;

  static AiProvider fromWire(String? value) => AiProvider.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => AiProvider.none,
      );
}

/// Everything needed to reach a provider.
@immutable
class AiProviderConfig {
  const AiProviderConfig({
    this.provider = AiProvider.none,
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
  });

  final AiProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  String get resolvedBaseUrl {
    final value = baseUrl.trim().isEmpty ? provider.defaultBaseUrl : baseUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String get resolvedModel =>
      model.trim().isEmpty ? provider.defaultModel : model.trim();

  /// Whether this config could reach anything at all.
  bool get isUsable =>
      provider != AiProvider.none &&
      apiKey.trim().isNotEmpty &&
      resolvedBaseUrl.isNotEmpty &&
      resolvedModel.isNotEmpty;

  AiProviderConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
  }) =>
      AiProviderConfig(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
      );
}

/// The outcome of a connection test, in the user's terms.
@immutable
class AiTestResult {
  const AiTestResult.ok(this.detail) : success = true;
  const AiTestResult.failed(this.detail) : success = false;

  final bool success;
  final String detail;
}

/// Talks to a configured provider over its HTTP API.
///
/// Only the capabilities a chat/embedding endpoint can actually serve are
/// implemented. Transcription and OCR stay null: they need audio and vision
/// endpoints that differ per provider and that two of the four do not offer at
/// all, and returning a wrong answer is worse than reporting "unavailable" —
/// which is exactly what a null means in this contract.
class CloudAIAdapter implements AIAdapter {
  CloudAIAdapter({required this.config, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final AiProviderConfig config;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> get _headers => switch (config.provider) {
        AiProvider.anthropic => {
            'content-type': 'application/json',
            'x-api-key': config.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
        _ => {
            'content-type': 'application/json',
            'authorization': 'Bearer ${config.apiKey.trim()}',
          },
      };

  Uri get _chatUri => Uri.parse(
        config.provider == AiProvider.anthropic
            ? '${config.resolvedBaseUrl}/v1/messages'
            : '${config.resolvedBaseUrl}/v1/chat/completions',
      );

  /// A single-turn completion, normalised across both API shapes.
  Future<String?> _complete(String system, String user, {int maxTokens = 300}) async {
    if (!config.isUsable) return null;
    final body = config.provider == AiProvider.anthropic
        ? {
            'model': config.resolvedModel,
            'max_tokens': maxTokens,
            'system': system,
            'messages': [
              {'role': 'user', 'content': user},
            ],
          }
        : {
            'model': config.resolvedModel,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          };
    final response = await _client
        .post(_chatUri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (config.provider == AiProvider.anthropic) {
      final content = decoded['content'];
      if (content is! List || content.isEmpty) return null;
      final first = content.first;
      return first is Map && first['text'] is String
          ? first['text'] as String
          : null;
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map)['message'];
    return message is Map && message['content'] is String
        ? message['content'] as String
        : null;
  }

  /// Reachability, credentials and model name, in one round trip.
  Future<AiTestResult> test() async {
    if (config.provider == AiProvider.none) {
      return const AiTestResult.failed('No provider selected');
    }
    if (config.apiKey.trim().isEmpty) {
      return const AiTestResult.failed('API key is empty');
    }
    if (config.resolvedBaseUrl.isEmpty) {
      return const AiTestResult.failed('Base URL is empty');
    }
    if (config.resolvedModel.isEmpty) {
      return const AiTestResult.failed('Model is empty');
    }
    try {
      final reply = await _complete('Reply with the single word: ok', 'ping', maxTokens: 8);
      if (reply == null) {
        return const AiTestResult.failed(
          'The provider rejected the request. Check the key and the model name.',
        );
      }
      return AiTestResult.ok(config.resolvedModel);
    } catch (error) {
      return AiTestResult.failed('$error');
    }
  }

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) {
    final text = _textOf(note);
    if (!config.isUsable || text == null) return null;
    return _suggestTags(text);
  }

  Future<List<TagSuggestion>> _suggestTags(String text) async {
    final reply = await _complete(
      'You label notes. Reply with 1-4 short tag names, comma separated, '
      'nothing else. Use the language the note is written in.',
      text,
      maxTokens: 60,
    );
    if (reply == null) return const [];
    return [
      for (final part in reply.split(','))
        if (part.trim().isNotEmpty && part.trim().length <= 32)
          TagSuggestion(name: part.trim()),
    ];
  }

  @override
  Future<Summary>? summarize(Note note) {
    final text = _textOf(note);
    if (!config.isUsable || text == null) return null;
    return _summarize(text);
  }

  Future<Summary> _summarize(String text) async {
    final reply = await _complete(
      'Summarise the note in one sentence, shorter than the original, '
      'in the language it is written in. Reply with the sentence only.',
      text,
      maxTokens: 200,
    );
    return Summary(text: reply?.trim() ?? '');
  }

  @override
  Future<Vector>? embed(String text) {
    // Anthropic publishes no embeddings endpoint; the others share OpenAI's.
    if (!config.isUsable || !config.provider.isOpenAiShaped) return null;
    return _embed(text);
  }

  Future<Vector> _embed(String text) async {
    final response = await _client
        .post(
          Uri.parse('${config.resolvedBaseUrl}/v1/embeddings'),
          headers: _headers,
          body: jsonEncode({
            'model': 'text-embedding-3-small',
            'input': text,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) return const Vector([]);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const Vector([]);
    final data = decoded['data'];
    if (data is! List || data.isEmpty) return const Vector([]);
    final values = (data.first as Map)['embedding'];
    if (values is! List) return const Vector([]);
    return Vector([for (final value in values) (value as num).toDouble()]);
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;

  @override
  Future<OCRText>? ocr(ImageRef image) => null;

  static String? _textOf(Note note) {
    final text = (note.content ?? note.transcriptText ?? note.ocrText)?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
