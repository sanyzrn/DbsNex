import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nex_core/nex_core.dart';

/// The cloud services Nex can talk to.
///
/// Three of them speak OpenAI's chat-completions shape and differ only in host,
/// model and nothing else. Anthropic and Gemini each have their own endpoint,
/// auth header and body — which is why a Google key pasted into "Custom" could
/// never work: it was being POSTed to `/v1/chat/completions` with a bearer
/// token, and Gemini serves neither that path nor that header.
enum AiProvider { none, anthropic, openai, gemini, openrouter, custom }

/// How a provider's HTTP requests are shaped.
enum AiWireFormat { openai, anthropic, gemini }

extension AiProviderWire on AiProvider {
  String get wireName => switch (this) {
    AiProvider.none => 'none',
    AiProvider.anthropic => 'anthropic',
    AiProvider.openai => 'openai',
    AiProvider.gemini => 'gemini',
    AiProvider.openrouter => 'openrouter',
    AiProvider.custom => 'custom',
  };

  String get label => switch (this) {
    AiProvider.none => 'On-device only',
    AiProvider.anthropic => 'Anthropic',
    AiProvider.openai => 'OpenAI',
    AiProvider.gemini => 'Google Gemini',
    AiProvider.openrouter => 'OpenRouter',
    AiProvider.custom => 'Custom (OpenAI-compatible)',
  };

  AiWireFormat get format => switch (this) {
    AiProvider.anthropic => AiWireFormat.anthropic,
    AiProvider.gemini => AiWireFormat.gemini,
    _ => AiWireFormat.openai,
  };

  String get defaultBaseUrl => switch (this) {
    AiProvider.none => '',
    AiProvider.anthropic => 'https://api.anthropic.com',
    AiProvider.openai => 'https://api.openai.com',
    AiProvider.gemini => 'https://generativelanguage.googleapis.com',
    AiProvider.openrouter => 'https://openrouter.ai/api',
    AiProvider.custom => '',
  };

  String get defaultModel => switch (this) {
    AiProvider.none => '',
    AiProvider.anthropic => 'claude-sonnet-4-5',
    AiProvider.openai => 'gpt-4o-mini',
    AiProvider.gemini => 'gemini-2.0-flash',
    AiProvider.openrouter => 'openai/gpt-4o-mini',
    AiProvider.custom => '',
  };

  /// Whether the endpoint has to be typed in.
  ///
  /// Only Custom does. Every other provider has exactly one host, and offering
  /// an editable Base URL for them was an invitation to fill in a field that
  /// could only ever make things worse — OpenRouter in particular, where the
  /// obvious guess (`https://openrouter.ai`) is missing the `/api` the real
  /// endpoint needs.
  bool get needsBaseUrl => this == AiProvider.custom;

  /// Whether the provider can read an image, so photo notes can be OCR'd.
  bool get readsImages => this != AiProvider.none;

  /// Whether the provider can listen to audio directly.
  ///
  /// Gemini takes audio inline. OpenAI has a separate transcription endpoint.
  /// Anthropic has neither, and OpenRouter's passthrough is not dependable
  /// enough to claim — "unavailable" beats a wrong answer.
  bool get hearsAudio => this == AiProvider.gemini || this == AiProvider.openai;

  /// Whether embeddings are available, for semantic search.
  bool get embeds =>
      this == AiProvider.openai ||
      this == AiProvider.openrouter ||
      this == AiProvider.custom ||
      this == AiProvider.gemini;

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
    final value = baseUrl.trim().isEmpty
        ? provider.defaultBaseUrl
        : baseUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String get resolvedModel =>
      model.trim().isEmpty ? provider.defaultModel : model.trim();

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
  }) => AiProviderConfig(
    provider: provider ?? this.provider,
    apiKey: apiKey ?? this.apiKey,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
  );
}

/// Which language the model is told to answer in.
///
/// Separate from the app's own locale on purpose. Someone can read the
/// interface in English and still want summaries of their Persian notes in
/// Persian — and, more often here, the reverse: Persian notes summarised in
/// Persian while the UI stays English. [auto] is the behaviour the app always
/// had, and stays the default.
enum AiOutputLanguage {
  auto('auto'),
  english('en'),
  persian('fa');

  const AiOutputLanguage(this.wireName);

  /// What gets persisted. The enum's own `name` would do it today, but it is
  /// a Dart identifier first and a storage key second; pinning the string
  /// means renaming a case later cannot silently reset everyone's choice.
  final String wireName;

  static AiOutputLanguage fromWire(String? value) => switch (value) {
    'en' => AiOutputLanguage.english,
    'fa' => AiOutputLanguage.persian,
    _ => AiOutputLanguage.auto,
  };

  /// The sentence appended to every system prompt.
  ///
  /// Named languages rather than locale codes: models follow "Reply in
  /// Persian (فارسی)" far more reliably than "Reply in fa", and naming the
  /// language in itself makes the instruction legible to the model in the
  /// script it is being asked to produce.
  String get promptRule => switch (this) {
    AiOutputLanguage.auto =>
      'Reply in the same language the notes are written in.',
    AiOutputLanguage.english =>
      'Reply in English, whatever language the notes are written in.',
    AiOutputLanguage.persian =>
      'Reply in Persian (فارسی), whatever language the notes are written in.',
  };
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
class CloudAIAdapter implements AIAdapter {
  CloudAIAdapter({
    required this.config,
    this.outputLanguage = AiOutputLanguage.auto,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final AiProviderConfig config;

  /// Which language every generated string comes back in. Defaults to the
  /// behaviour that predates the setting, so a caller that has no opinion —
  /// every test, and the connection check — is unaffected.
  final AiOutputLanguage outputLanguage;
  final http.Client _client;
  final bool _ownsClient;

  /// Generous on purpose. A free tier can take the better part of a minute to
  /// answer, and a request that is still in flight is not a failure — the
  /// previous thirty seconds turned "slow" into "this feature does not work".
  static const _textTimeout = Duration(seconds: 90);

  /// Longer still: the request carries a whole audio or image file.
  static const _mediaTimeout = Duration(minutes: 3);

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> get _headers => switch (config.provider.format) {
    AiWireFormat.anthropic => {
      'content-type': 'application/json',
      'x-api-key': config.apiKey.trim(),
      'anthropic-version': '2023-06-01',
    },
    // Gemini takes its key as a query parameter (see [_withKey]), so the
    // request carries no auth header at all. It also accepts
    // `x-goog-api-key`, but sending the key in the URL is the form Google's
    // own quickstarts use and the one verified to work against this
    // account — and a request that authenticates two ways is a request
    // with two ways to be wrong.
    AiWireFormat.gemini => {'content-type': 'application/json'},
    AiWireFormat.openai => {
      'content-type': 'application/json',
      'authorization': 'Bearer ${config.apiKey.trim()}',
    },
  };

  Uri get _chatUri => switch (config.provider.format) {
    AiWireFormat.anthropic => Uri.parse(
      '${config.resolvedBaseUrl}/v1/messages',
    ),
    AiWireFormat.gemini => _withKey(
      '${config.resolvedBaseUrl}/v1beta/models/'
      '${config.resolvedModel}:generateContent',
    ),
    AiWireFormat.openai => Uri.parse(
      '${config.resolvedBaseUrl}/v1/chat/completions',
    ),
  };

  /// Gemini's `?key=` form.
  Uri _withKey(String url) =>
      Uri.parse(url).replace(queryParameters: {'key': config.apiKey.trim()});

  /// What the provider said the last time it refused, or null.
  ///
  /// Every AI path treats a non-200 as "no answer" and carries on, which is
  /// right for enrichment — a failed summary must not break capture. But it
  /// meant [test] could only ever report "the provider rejected the request"
  /// no matter what happened, so a wrong key, a retired model and a rate limit
  /// were indistinguishable from each other and from a typo in the model name.
  /// The adapter is constructed fresh for each test, so one field is enough.
  ({int status, String? message})? _lastFailure;

  /// One turn, with optional inline media, normalised across all three shapes.
  Future<String?> _complete(
    String system,
    String user, {
    int maxTokens = 300,
    Uint8List? media,
    String? mediaMimeType,
  }) async {
    if (!config.isUsable) return null;
    final base64Media = media == null ? null : base64Encode(media);

    final body = switch (config.provider.format) {
      AiWireFormat.anthropic => {
        'model': config.resolvedModel,
        'max_tokens': maxTokens,
        'system': system,
        'messages': [
          {
            'role': 'user',
            'content': [
              if (base64Media != null)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mediaMimeType ?? 'image/jpeg',
                    'data': base64Media,
                  },
                },
              {'type': 'text', 'text': user},
            ],
          },
        ],
      },
      AiWireFormat.gemini => {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              if (base64Media != null)
                {
                  'inline_data': {
                    'mime_type': mediaMimeType ?? 'application/octet-stream',
                    'data': base64Media,
                  },
                },
              {'text': user},
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': maxTokens},
      },
      AiWireFormat.openai => {
        'model': config.resolvedModel,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {
            'role': 'user',
            'content': base64Media == null
                ? user
                : [
                    {'type': 'text', 'text': user},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:${mediaMimeType ?? 'image/jpeg'};base64,$base64Media',
                      },
                    },
                  ],
          },
        ],
      },
    };

    final response = await _client
        .post(_chatUri, headers: _headers, body: jsonEncode(body))
        .timeout(media == null ? _textTimeout : _mediaTimeout);
    if (response.statusCode != 200) {
      _lastFailure = (
        status: response.statusCode,
        message: _extractError(response.body),
      );
      return null;
    }
    _lastFailure = null;
    return _extractText(response.body);
  }

  /// The provider's own explanation, whichever shape it arrived in.
  ///
  /// All three wrap it differently — Gemini and OpenAI in `error.message`,
  /// Anthropic in `error.message` too but under a different envelope — and the
  /// message is the only part worth showing: "API key not valid" and "model
  /// not found for API version v1beta" are the two answers a person actually
  /// needs, and both were being thrown away.
  @visibleForTesting
  static String? extractErrorForTest(String body) => _extractError(body);

  static String? _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {
      // Not JSON — an HTML error page from a proxy, most likely.
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }

  @visibleForTesting
  String? extractTextForTest(String body) => _extractText(body);

  String? _extractText(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    switch (config.provider.format) {
      case AiWireFormat.anthropic:
        final content = decoded['content'];
        if (content is! List) return null;
        for (final part in content) {
          if (part is Map && part['text'] is String) {
            return part['text'] as String;
          }
        }
        return null;
      case AiWireFormat.gemini:
        final candidates = decoded['candidates'];
        if (candidates is! List || candidates.isEmpty) return null;
        final content = (candidates.first as Map)['content'];
        if (content is! Map) return null;
        final parts = content['parts'];
        if (parts is! List) return null;
        // Concatenate: Gemini splits a long answer across parts, and taking
        // only the first would silently truncate it.
        final buffer = StringBuffer();
        for (final part in parts) {
          if (part is Map && part['text'] is String) buffer.write(part['text']);
        }
        final text = buffer.toString();
        return text.isEmpty ? null : text;
      case AiWireFormat.openai:
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) return null;
        final message = (choices.first as Map)['message'];
        return message is Map && message['content'] is String
            ? message['content'] as String
            : null;
    }
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
      // Not 8. A reasoning model spends its output budget on thinking tokens
      // before it writes a word, so a tiny ceiling comes back as a 200 with
      // `finishReason: MAX_TOKENS` and no text at all — which read here as
      // "the provider rejected the request" on a provider that was working
      // perfectly. The budget has to be large enough for the model to think
      // and still answer.
      final reply = await _complete(
        'Reply with the single word: ok',
        'ping',
        maxTokens: 256,
      );
      if (reply != null) return AiTestResult.ok(config.resolvedModel);

      final failure = _lastFailure;
      if (failure == null) {
        return const AiTestResult.failed(
          'The provider answered, but with no text. The model may have '
          'stopped on a content filter.',
        );
      }
      return AiTestResult.failed(_describe(failure.status, failure.message));
    } catch (error) {
      return AiTestResult.failed('$error');
    }
  }

  /// An HTTP status, said in the terms of the thing the person has to fix.
  static String _describe(int status, String? message) {
    final detail = message == null ? '' : ' — $message';
    return switch (status) {
      401 || 403 =>
        'The key was rejected ($status). Check that it is correct and still '
            'active.$detail',
      404 =>
        'Not found (404). The model name is probably wrong or retired.$detail',
      429 => 'Rate limited (429). Wait a moment and try again.$detail',
      >= 500 => 'The provider had a server error ($status).$detail',
      _ => 'The provider returned $status.$detail',
    };
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
      'nothing else. ${outputLanguage.promptRule}',
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
      'Summarise the note in one sentence, shorter than the original. '
      'Reply with the sentence only. ${outputLanguage.promptRule}',
      text,
      maxTokens: 200,
    );
    return Summary(text: reply?.trim() ?? '');
  }

  /// A warm, two-sentence recap of what someone has been capturing lately.
  ///
  /// Not part of [AIAdapter]: every other capability there takes one [Note],
  /// because enrichment is a per-note pipeline. This is the one place in the
  /// app that wants "here is a handful of recent notes, say something about
  /// them" rather than "extract something from this one" — it belongs to the
  /// timeline's own daily-summary panel, not to the note-scoped contract.
  ///
  /// The word budget is stated in the prompt *and* enforced on the way out by
  /// [_clamped]: models treat "at most 30 words" as a suggestion, and the
  /// panel this lands in is a card with two lines of room. A recap that
  /// overflows it is worse than a shorter one.
  Future<String?> digest(String recentNotesText) async {
    if (!config.isUsable || recentNotesText.trim().isEmpty) return null;
    final reply = await _complete(
      'You write the short recap a notes app shows someone when they open '
      "it: warm, a little funny, never corporate. You're given a handful of "
      'their recent notes. Write ONE or TWO short sentences — at most 30 '
      "words in total — touching on what they've been capturing. No preamble, "
      'no heading, no bullet points, no quotes, no emoji. Reply with the '
      'recap only. ${outputLanguage.promptRule}',
      recentNotesText,
      maxTokens: 160,
    );
    return _clamped(reply, 30);
  }

  /// The one-line headline over the timeline: a mood, not a summary.
  ///
  /// Deliberately a different call from [digest] rather than a longer prompt
  /// on the same one. This is a *title* — it sits at display size, wraps to at
  /// most two lines, and is regenerated whenever the user taps it, so it has
  /// to come back short every single time. Asking one prompt for both a title
  /// and a recap reliably produced a paragraph for each.
  ///
  /// The reader's name is deliberately *not* part of this. `displayName` has
  /// never left the device and does not start now for a decoration — the name
  /// is rendered beside this line by the app itself, where it costs nothing.
  Future<String?> headline(String recentNotesText) async {
    if (!config.isUsable) return null;
    final reply = await _complete(
      'You write the single line a notes app shows across the top of its home '
      'screen when it opens. One sentence, at most 9 words, ending with one '
      'emoji that fits it. Evocative and warm — a mood tied to the time of '
      'day and, loosely, to what they have been noting. Never a summary, '
      'never a question, never an instruction, never a heading, no quotes, '
      'never address anyone by name. Reply with the line only. '
      '${outputLanguage.promptRule}',
      recentNotesText.trim().isEmpty
          ? 'They have not written anything yet. The local time is '
                '${DateTime.now().hour}:00.'
          : 'The local time is ${DateTime.now().hour}:00. Their recent '
                'notes:\n$recentNotesText',
      maxTokens: 60,
    );
    return _clamped(reply, 12);
  }

  /// Trims a reply to [maxWords], cutting at a sentence end when one is near
  /// enough and simply dropping the tail otherwise.
  ///
  /// Returns null for an empty reply so callers can treat "the model said
  /// nothing" and "there is no provider" the same way.
  static String? _clamped(String? reply, int maxWords) {
    final text = reply?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text == null || text.isEmpty) return null;
    final words = text.split(' ');
    if (words.length <= maxWords) return text;
    final cut = words.take(maxWords).join(' ');
    // Prefer ending where the model ended a sentence, rather than mid-clause
    // with an ellipsis — but only if that does not throw most of it away.
    final stop = cut.lastIndexOf(RegExp(r'[.!?…؟۔]'));
    if (stop > cut.length ~/ 2) return cut.substring(0, stop + 1);
    return '$cut…';
  }

  @override
  Future<OCRText>? ocr(ImageRef image) {
    if (!config.isUsable || !config.provider.readsImages) return null;
    final bytes = image.bytes ?? _read(image.mediaUri);
    if (bytes == null) return null;
    return _ocr(bytes, image.mediaUri);
  }

  Future<OCRText> _ocr(Uint8List bytes, String uri) async {
    final reply = await _complete(
      'Transcribe every readable word in the image, in reading order. '
          'Reply with the text only. If there is no text, reply with nothing.',
      'What does this image say?',
      maxTokens: 800,
      media: bytes,
      mediaMimeType: _imageMime(uri),
    );
    return OCRText(text: reply?.trim() ?? '');
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    if (!config.isUsable || !config.provider.hearsAudio) return null;
    final bytes = audio.bytes ?? _read(audio.mediaUri);
    if (bytes == null) return null;
    return _transcribe(bytes, audio.mediaUri);
  }

  Future<Transcript> _transcribe(Uint8List bytes, String uri) async {
    // Gemini takes audio inline, in the same call shape as everything else.
    if (config.provider.format == AiWireFormat.gemini) {
      final reply = await _complete(
        'Transcribe the speech in the audio, in its own language. '
            'Reply with the transcript only.',
        'Transcribe this recording.',
        maxTokens: 2000,
        media: bytes,
        mediaMimeType: _audioMime(uri),
      );
      return Transcript(text: reply?.trim() ?? '');
    }
    // OpenAI has a dedicated multipart endpoint instead.
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${config.resolvedBaseUrl}/v1/audio/transcriptions'),
          )
          ..headers['authorization'] = 'Bearer ${config.apiKey.trim()}'
          ..fields['model'] = 'whisper-1'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: uri.split(Platform.pathSeparator).last,
            ),
          );
    final streamed = await _client.send(request).timeout(_mediaTimeout);
    if (streamed.statusCode != 200) return const Transcript(text: '');
    final body = await streamed.stream.bytesToString();
    final decoded = jsonDecode(body);
    final text = decoded is Map && decoded['text'] is String
        ? decoded['text'] as String
        : '';
    return Transcript(text: text.trim());
  }

  @override
  Future<Vector>? embed(String text) {
    if (!config.isUsable || !config.provider.embeds) return null;
    return _embed(text);
  }

  Future<Vector> _embed(String text) async {
    if (config.provider.format == AiWireFormat.gemini) {
      final response = await _client
          .post(
            // Same `?key=` form as the chat endpoint — the Gemini headers no
            // longer carry the key, so parsing this URL plainly would send an
            // unauthenticated request.
            _withKey(
              '${config.resolvedBaseUrl}'
              '/v1beta/models/text-embedding-004:embedContent',
            ),
            headers: _headers,
            body: jsonEncode({
              'model': 'models/text-embedding-004',
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
            }),
          )
          .timeout(_textTimeout);
      if (response.statusCode != 200) return const Vector([]);
      final decoded = jsonDecode(response.body);
      // Spelled out rather than chained: `cond ? a?['b'] : c` puts a `?[` where
      // the parser is still expecting the ternary's true branch.
      if (decoded is! Map) return const Vector([]);
      final embedding = decoded['embedding'];
      if (embedding is! Map) return const Vector([]);
      final values = embedding['values'];
      if (values is! List) return const Vector([]);
      return Vector([for (final value in values) (value as num).toDouble()]);
    }
    final response = await _client
        .post(
          Uri.parse('${config.resolvedBaseUrl}/v1/embeddings'),
          headers: _headers,
          body: jsonEncode({'model': 'text-embedding-3-small', 'input': text}),
        )
        .timeout(_textTimeout);
    if (response.statusCode != 200) return const Vector([]);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const Vector([]);
    final data = decoded['data'];
    if (data is! List || data.isEmpty) return const Vector([]);
    final values = (data.first as Map)['embedding'];
    if (values is! List) return const Vector([]);
    return Vector([for (final value in values) (value as num).toDouble()]);
  }

  static Uint8List? _read(String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  static String _imageMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _audioMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mp3';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.aac')) return 'audio/aac';
    return 'audio/mp4';
  }

  static String? _textOf(Note note) {
    final text = (note.content ?? note.transcriptText ?? note.ocrText)?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
