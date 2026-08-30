import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nex_core/nex_core.dart';

import 'assistant_actions.dart';

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

/// How far the assistant is allowed to wander from the plainest answer.
///
/// Three named stops rather than a 0–2 slider. Temperature is a sampling
/// parameter, not a personality dial, and a number with no units invites
/// fiddling that mostly produces worse answers — the useful range for a
/// notes assistant is narrow, and these are its ends and its middle.
enum AiCreativity {
  precise('precise', 0.15),
  balanced('balanced', 0.7),
  inventive('inventive', 1.05);

  const AiCreativity(this.wireName, this.temperature);

  final String wireName;
  final double temperature;

  static AiCreativity fromWire(String? value) => AiCreativity.values.firstWhere(
    (candidate) => candidate.wireName == value,
    orElse: () => AiCreativity.balanced,
  );
}

/// How long an answer is allowed to be.
///
/// A token budget rather than a word count, because that is what the
/// providers take — but it is also stated in the prompt, since a budget
/// alone does not shorten an answer, it truncates one. The two together are
/// what produce a short answer rather than a long answer cut off mid-word.
enum AiAnswerLength {
  brief('brief', 220, 'Answer in one or two sentences.'),
  standard('standard', 700, 'Answer in a short paragraph at most.'),
  full('full', 1800, 'Answer at whatever length the question needs.');

  const AiAnswerLength(this.wireName, this.maxTokens, this.promptRule);

  final String wireName;
  final int maxTokens;
  final String promptRule;

  static AiAnswerLength fromWire(String? value) =>
      AiAnswerLength.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => AiAnswerLength.standard,
      );
}

enum AiResponseStyle {
  natural(
    'natural',
    'Sound natural, calm, and human. Match the user without imitating them.',
  ),
  friendly(
    'friendly',
    'Be friendly, encouraging, and conversational without becoming sugary.',
  ),
  formal(
    'formal',
    'Use a polished, respectful, professional tone and avoid slang.',
  ),
  serious(
    'serious',
    'Be direct, sober, and focused. Avoid jokes, flattery, and playful phrasing.',
  ),
  romantic(
    'romantic',
    'Answer affectionately and romantically. Use gentle endearments and caring praise, while respecting boundaries and never implying a real human relationship.',
  ),
  /// Whatever the user wrote, in place of a preset.
  ///
  /// Empty rule on purpose: under this style the instruction *is* the rule,
  /// and it is added further down where it can be quoted and labelled as the
  /// user's own words rather than the app's.
  custom('custom', '');

  const AiResponseStyle(this.wireName, this.promptRule);

  final String wireName;
  final String promptRule;

  static AiResponseStyle fromWire(String? value) =>
      AiResponseStyle.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => AiResponseStyle.natural,
      );
}

/// Everything the assistant sheet decides about one exchange.
///
/// Grouped rather than passed as five parameters: they are read together,
/// stored together, and every one of them is a user setting, so a caller that
/// forgets one gets the app's default instead of the wire format's.
@immutable
class AiChatOptions {
  const AiChatOptions({
    this.creativity = AiCreativity.balanced,
    this.length = AiAnswerLength.standard,
    this.notesOnly = true,
    this.notesContext = '',
    this.canAct = false,
    this.instruction = '',
    this.responseStyle = AiResponseStyle.natural,
    this.userName = '',
    this.userIntroduction = '',
  });

  final AiCreativity creativity;
  final AiAnswerLength length;

  /// Whether the assistant stays inside the user's notes and the app itself.
  ///
  /// On by default. This is the assistant in a notes app, not a general
  /// chatbot: a model answering trivia here is both off-topic and — on the
  /// small free-tier models this app is usually pointed at — worse at it than
  /// anything else the user could ask. Off, it answers anything.
  final bool notesOnly;

  /// The user's recent notes, already formatted, or empty.
  ///
  /// Never their whole library: a prompt is a network request to a third
  /// party, and the amount of someone's writing that leaves the device is a
  /// setting rather than an implementation detail.
  final String notesContext;

  /// Whether the assistant may ask to create, edit, delete or re-tag a note.
  ///
  /// "Ask" is the whole word: nothing it returns is applied without the user
  /// pressing a button. See [assistantActionPrompt].
  final bool canAct;

  /// The user's own standing instruction, in their words — "answer with a bit
  /// of humour", "always in Persian", "keep it to three lines".
  ///
  /// A preference about *manner*, not a second set of rules. It goes in after
  /// the app's own brief and before everything that constrains what the
  /// assistant may do, so a request to be funny changes the tone and a request
  /// to ignore the scope or the action protocol does not survive the lines
  /// that follow it.
  final String instruction;
  final AiResponseStyle responseStyle;
  final String userName;
  final String userIntroduction;
}

/// The outcome of a connection test, in the user's terms.
@immutable
class AiTestResult {
  const AiTestResult.ok(this.detail) : success = true;
  const AiTestResult.failed(this.detail) : success = false;

  final bool success;
  final String detail;
}

/// Whether the app can produce text right now, by either route.
///
/// The UI asks this instead of [AiProviderConfig.isUsable] wherever it is
/// deciding whether to offer something. A phone with a downloaded model and no
/// API key can write a recap, answer the assistant and translate a note, and a
/// screen gated on `isUsable` alone hides all three from the person who just
/// spent two gigabytes getting them.
///
/// Not used by the database worker, deliberately. Enrichment runs in its own
/// isolate, and a binding is per-isolate — but the deeper reason is that
/// enrichment happens on save, and capture must never wait on a model this
/// large. Tag hints there stay with the fast heuristics.
bool aiTextAvailableWith(AiProviderConfig config) =>
    config.isUsable || ChatAdapterBinding.instance.available;

/// Talks to a configured provider over its HTTP API — or, when there is no
/// provider and a model has been downloaded, to that model on this phone.
///
/// The local path is not a second adapter. Every text feature in the app funnels
/// through [_complete] or [chat], so routing at those two points gives the
/// on-device model to all of them at once — the daily recap, the headline, tag
/// suggestions, summaries, translation and the assistant — instead of five
/// call sites each learning about it.
///
/// It reaches the model through `ChatAdapterBinding`, a `nex_core` port, and
/// never through `packages/ai`. That is the whole point of the port: this file
/// compiles unchanged in the standard flavor, where nothing binds an
/// implementation and [ChatAdapter.available] is simply false (ADR-031).
///
/// What the local model deliberately does *not* serve: transcription, reading
/// text out of an image, and embeddings. Those need a model that hears or sees,
/// and this one only reads and writes text. They stay cloud-only and stay
/// honestly unavailable, rather than being wired to something that would
/// confidently invent a transcript.
class CloudAIAdapter implements AIAdapter {
  CloudAIAdapter({
    required this.config,
    this.outputLanguage = AiOutputLanguage.auto,
    http.Client? client,
    @visibleForTesting ChatAdapter? localModel,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _localOverride = localModel;

  final AiProviderConfig config;

  /// Injected only by tests. Production reads the process-wide binding every
  /// time rather than capturing it, because a model can finish downloading —
  /// or be deleted — while an adapter built at app start is still alive.
  final ChatAdapter? _localOverride;

  ChatAdapter get _local => _localOverride ?? ChatAdapterBinding.instance;

  /// Whether this adapter can answer at all, by either route.
  ///
  /// The UI asks this rather than `config.isUsable`: with a model on the phone
  /// and no API key, the assistant works, and a screen that hid it would be
  /// hiding a feature the user has already paid two gigabytes for.
  bool get canAnswerText => config.isUsable || _local.available;

  /// True when there is no provider but there is a model — the case where a
  /// request should go to the phone instead of the network.
  bool get _preferLocal => !config.isUsable && _local.available;

  /// Runs one exchange against the on-device model.
  ///
  /// The system text becomes a [ChatRole.system] message rather than being
  /// glued to the front of the user's words, because the adapter on the other
  /// side maps that role onto LiteRT-LM's own system-instruction slot.
  Future<String?> _completeLocally(String system, String user) async {
    final pending = _local.sendMessage([
      if (system.trim().isNotEmpty)
        ChatMessage(role: ChatRole.system, content: system),
      ChatMessage(role: ChatRole.user, content: user),
    ]);
    // Null before awaiting is the contract's way of saying "not available" —
    // the model was deleted between the check above and here, for instance.
    if (pending == null) return null;
    try {
      final reply = await pending;
      final text = reply.content.trim();
      return text.isEmpty ? null : text;
    } catch (error) {
      // A model that fails to load, or a backend that dies mid-answer. Treated
      // exactly like a provider returning 500: null, and the caller shows what
      // it shows when there is no answer.
      _lastFailure = (status: 0, message: '$error');
      return null;
    }
  }

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
    // Gemini takes its key in the `x-goog-api-key` header, the same way the
    // other two formats carry their credential in a header. It used to ride
    // in a `?key=` query parameter — the form Google's quickstarts use — but
    // a key in a URL is a key in every proxy and server log that ever sees
    // the request line, and this app sends notes to that provider. One
    // header, one way to authenticate.
    AiWireFormat.gemini => {
      'content-type': 'application/json',
      'x-goog-api-key': config.apiKey.trim(),
    },
    AiWireFormat.openai => {
      'content-type': 'application/json',
      'authorization': 'Bearer ${config.apiKey.trim()}',
    },
  };

  Uri get _chatUri => switch (config.provider.format) {
    AiWireFormat.anthropic => Uri.parse(
      '${config.resolvedBaseUrl}/v1/messages',
    ),
    AiWireFormat.gemini => Uri.parse(
      '${config.resolvedBaseUrl}/v1beta/models/'
      '${config.resolvedModel}:generateContent',
    ),
    AiWireFormat.openai => Uri.parse(
      '${config.resolvedBaseUrl}/v1/chat/completions',
    ),
  };

  /// What the provider said the last time it refused, or null.
  ///
  /// Every AI path treats a non-200 as "no answer" and carries on, which is
  /// right for enrichment — a failed summary must not break capture. But it
  /// meant [test] could only ever report "the provider rejected the request"
  /// no matter what happened, so a wrong key, a retired model and a rate limit
  /// were indistinguishable from each other and from a typo in the model name.
  /// The adapter is constructed fresh for each test, so one field is enough.
  ({int status, String? message})? _lastFailure;

  /// What went wrong on the last request, when it is worth repeating verbatim.
  ///
  /// Only for the local path, and only for a message the runtime produced
  /// itself. A cloud failure already has [_describe] to turn a status code
  /// into something someone can act on; a model that will not load has no
  /// status code and no vocabulary but its own, and "no answer came back,
  /// check the provider in Settings" is actively misleading advice to give
  /// someone who chose to have no provider.
  String? get localFailure => _preferLocal ? _lastFailure?.message : null;

  /// One turn, with optional inline media, normalised across all three shapes.
  Future<String?> _complete(
    String system,
    String user, {
    int maxTokens = 300,
    Uint8List? media,
    String? mediaMimeType,
  }) async {
    if (!config.isUsable) {
      // No provider. If a model is on the phone this still has an answer —
      // unless the request carries an image, which is the one thing the local
      // path cannot take, so that stays unavailable rather than silently
      // dropping the picture and answering about nothing.
      if (_preferLocal && media == null) return _completeLocally(system, user);
      return null;
    }
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
        message: _extractError(_bodyText(response)),
      );
      return null;
    }
    _lastFailure = null;
    return _extractText(_bodyText(response));
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
    if (!canAnswerText || text == null) return null;
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
    if (!canAnswerText || text == null) return null;
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
    if (!canAnswerText || recentNotesText.trim().isEmpty) return null;
    final reply = await _complete(
      'You write the short recap a notes app shows someone when they open '
      "it. You're given a handful of their recent notes. Write ONE or TWO "
      'short sentences, at most 30 words in total, that show you actually '
      'read them: name the real thing they wrote about, not the category it '
      'belongs to — "the cooler and the plane tickets", not "errands and '
      'travel plans". The tone is a friend reading over their shoulder: dry, '
      'warm, occasionally funny. Never motivational, never corporate, never '
      'flattering, no advice, no questions. No preamble, no heading, no '
      'bullet points, no quotes, no emoji. Write in one language only. '
      'Reply with the recap only. ${outputLanguage.promptRule}',
      recentNotesText,
      maxTokens: 160,
    );
    return _plausible(_clamped(reply, 30));
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
  Future<String?> headline(
    String recentNotesText, {
    AiOutputLanguage? language,
  }) async {
    if (!canAnswerText) return null;
    final reply = await _complete(
      'You write the greeting a notes app opens with. Not a sentence — a '
      'short phrase of two to five words that a name can follow, the way '
      '"Good morning" precedes one. It is a mood tied to the hour and, '
      'lightly, to what they have been writing down. Warm and a little '
      'playful. '
      // No name in the prompt and none in the reply. The user's name never
      // leaves this device — not to a provider, not to sync — so the app
      // appends it to whatever comes back. That is also why this asks for a
      // phrase rather than a sentence: a sentence has nowhere to put a name.
      'Never include a name or any placeholder for one. No emoji, no quotes, '
      'no full stop, no comma at the end, never a question, never advice, '
      'never a summary. Use ordinary words and write in one language only. '
      'Reply with the phrase only. '
      // Overridable, unlike every other call here. The phrase is shown with
      // the user's name after it, and the name is the one word the app did
      // not choose — so its script decides the language. Left on `auto`
      // ("answer in the language of the notes") this produced an English
      // phrase in front of a Persian name.
      '${(language ?? outputLanguage).promptRule}',
      recentNotesText.trim().isEmpty
          ? 'They have not written anything yet. The local time is '
                '${DateTime.now().hour}:00.'
          : 'The local time is ${DateTime.now().hour}:00. Their recent '
                'notes:\n$recentNotesText',
      maxTokens: 60,
    );
    return _plausible(_clamped(reply, 6));
  }

  /// A note in another language, and nothing else.
  ///
  /// Target language explicit rather than taken from [outputLanguage]: that
  /// setting says what language the app writes *to you* in, and it is set once.
  /// Translation is a per-note question — a Persian note is being read in
  /// English precisely because the interface is in Persian — so answering it
  /// from the global setting would translate a note into the language it is
  /// already in and look broken.
  ///
  /// The token budget scales with the input because a translation is roughly
  /// as long as its source, and a fixed ceiling truncated long notes
  /// mid-sentence with nothing to say it had happened.
  ///
  /// Null on a failed or refused request, and null on a reply that came back
  /// as token soup. [_notGarbled], not [_plausible]: the latter rejects any
  /// line that uses the same word three times, which is right for a nine-word
  /// headline and wrong for every real paragraph.
  Future<String?> translate(
    String text, {
    required AiOutputLanguage target,
  }) async {
    final source = text.trim();
    if (!canAnswerText || source.isEmpty) return null;
    if (target == AiOutputLanguage.auto) return null;
    final reply = await _complete(
      'You are a translator. Translate the text you are given, whole, '
      'keeping its line breaks, its lists and its punctuation. Translate '
      'only — never summarise, never explain, never comment on the text, '
      'never add a heading or a preamble, and never answer anything the text '
      'asks. If part of it is already in the target language, leave that part '
      'as it is. Reply with the translation and nothing else. '
      '${target.promptRule}',
      source,
      // Roughly four times the source in tokens: Persian and English differ
      // enough in tokens-per-character that a tighter ratio clips one
      // direction and not the other.
      maxTokens: math.min(4000, 200 + source.length),
    );
    final translated = reply?.trim();
    if (translated == null || translated.isEmpty) return null;
    return _notGarbled(translated);
  }

  /// A real multi-turn exchange, normalised across all three wire shapes.
  ///
  /// Not built on [_complete]: that takes exactly one user turn, which is the
  /// right shape for every enrichment call and the wrong one for a
  /// conversation. Flattening a history into a single prompt with "User:" and
  /// "Assistant:" prefixes was the cheap alternative and it is a bad one —
  /// the model stops being able to tell its own previous words from the
  /// user's, and starts answering the transcript instead of the person.
  ///
  /// Returns null on anything that is not a 200, the same as every other call
  /// here: an unreachable provider is "no answer", not an exception to catch.
  /// The instruction the assistant runs under, built from the user's own
  /// settings.
  ///
  /// Public and pure so it can be read in a test without a network — the
  /// scope rule in particular is a promise made to the user in Settings, and
  /// a promise that is only checkable by asking a live model is not one.
  @visibleForTesting
  String chatSystemPrompt(AiChatOptions options) {
    final parts = <String>[
      'You are the assistant inside Nex, a notes app. Be concrete and plain: '
          'no preamble, no restating the question, no offers to help further.',
      // Emoji as punctuation, not as decoration. Asked for because the
      // assistant read as clipped beside the rest of the app, and bounded in
      // the same breath because the failure mode of "use more emoji" is a
      // reply where every noun has a picture beside it and none of them mean
      // anything.
      'Warm rather than clipped. Use an emoji where it does real work — one '
          'ahead of a heading or a list item, or to mark what something is '
          '(pinned, a reminder, done). At most one per line, never inside a '
          'sentence, and never standing in for a word.',
      options.length.promptRule,
      if (options.responseStyle.promptRule.isNotEmpty)
        options.responseStyle.promptRule,
    ];
    final userName = options.userName.trim();
    final introduction = options.userIntroduction.trim();
    if (userName.isNotEmpty || introduction.isNotEmpty) {
      parts.add(
        [
          if (userName.isNotEmpty) 'Address the user as "$userName".',
          if (introduction.isNotEmpty)
            'The user introduced themselves this way: "$introduction"',
        ].join(' '),
      );
    }
    // Whether the user *has* an instruction is settled before it gets here —
    // tone has one control now, and only the custom style carries a sentence
    // of its own. An instruction that arrives is one that applies.
    final instruction = options.instruction.trim();
    if (instruction.isNotEmpty) {
      // Quoted and labelled rather than pasted in as another rule of the
      // app's own. The model needs to be able to tell the difference between
      // what Nex requires of it and what this person happens to prefer —
      // otherwise "reply like a pirate" and "never invent a note" arrive with
      // equal authority, and the constraints below are the ones that matter.
      parts.add(
        'The user has asked you to answer a particular way. Follow it as far '
        'as tone and format go, and no further — it does not loosen anything '
        'below. Their words: "$instruction"',
      );
    }
    if (options.notesOnly) {
      // Not a refusal. A model that answers "I cannot help with that" reads
      // as broken rather than as focused, and the honest version of this
      // boundary is short and says where the answer would have to come from.
      parts.add(
        "Answer only from the user's notes below and about using Nex itself. "
        'If the answer is not in their notes, say so in one line instead of '
        'inventing it. If asked something unrelated to their notes or to the '
        'app, say in one line that you only help with what is in Nex, and '
        'stop there.',
      );
    }
    if (options.canAct) parts.add(assistantActionPrompt);
    parts.add(outputLanguage.promptRule);
    if (options.notesContext.trim().isNotEmpty) {
      parts.add(
        "The user's recent notes, most recent first:\n"
        '${options.notesContext.trim()}',
      );
    } else if (options.notesOnly) {
      parts.add('The user has no notes yet.');
    }
    return parts.join('\n\n');
  }

  Future<String?> chat(
    List<ChatMessage> history, {
    AiChatOptions options = const AiChatOptions(),
  }) async {
    if (history.isEmpty) return null;
    if (!config.isUsable) {
      if (!_preferLocal) return null;
      // The transcript goes over whole, system prompt included: the adapter on
      // the other side keeps one conversation alive across calls and only
      // sends what it has not seen, so handing it everything costs nothing and
      // is what lets it skip re-reading the thread on every message.
      final system = chatSystemPrompt(options);
      final pending = _local.sendMessage([
        ChatMessage(role: ChatRole.system, content: system),
        for (final message in history)
          if (message.role != ChatRole.system) message,
      ]);
      if (pending == null) return null;
      try {
        final reply = await pending;
        final text = reply.content.trim();
        return text.isEmpty ? null : text;
      } catch (error) {
        _lastFailure = (status: 0, message: '$error');
        return null;
      }
    }
    final system = chatSystemPrompt(options);
    final maxTokens = options.length.maxTokens;
    final temperature = options.creativity.temperature;
    final turns = [
      for (final message in history)
        if (message.role != ChatRole.system) message,
    ];

    final body = switch (config.provider.format) {
      AiWireFormat.anthropic => {
        'model': config.resolvedModel,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'system': system,
        'messages': [
          for (final turn in turns)
            {
              'role': turn.role == ChatRole.assistant ? 'assistant' : 'user',
              'content': turn.content,
            },
        ],
      },
      // Gemini calls the assistant "model", and carries the system prompt
      // outside the turn list rather than as the first turn.
      AiWireFormat.gemini => {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          for (final turn in turns)
            {
              'role': turn.role == ChatRole.assistant ? 'model' : 'user',
              'parts': [
                {'text': turn.content},
              ],
            },
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': temperature,
        },
      },
      AiWireFormat.openai => {
        'model': config.resolvedModel,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'messages': [
          {'role': 'system', 'content': system},
          for (final turn in turns)
            {
              'role': turn.role == ChatRole.assistant ? 'assistant' : 'user',
              'content': turn.content,
            },
        ],
      },
    };

    final response = await _client
        .post(_chatUri, headers: _headers, body: jsonEncode(body))
        .timeout(_textTimeout);
    if (response.statusCode != 200) {
      _lastFailure = (
        status: response.statusCode,
        message: _extractError(_bodyText(response)),
      );
      return null;
    }
    _lastFailure = null;
    return _extractText(_bodyText(response))?.trim();
  }

  /// The response body, decoded as UTF-8 whatever the provider said.
  ///
  /// `http.Response.body` follows the charset in the Content-Type header and
  /// falls back to latin1 when there is none, which is the letter of the HTTP
  /// spec and wrong for every provider here: they all send UTF-8, and several
  /// send it under a bare `application/json`. A Persian reply then came back
  /// as mojibake — from a request that succeeded, so nothing anywhere
  /// reported a failure.
  static String _bodyText(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

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

  /// Drops a reply that is not a sentence at all.
  ///
  /// The two decorative lines — the headline and the daily recap — are the
  /// only places in the app where a model's raw words are shown as the app's
  /// own voice, with nothing around them to make a bad one legible as a bad
  /// one. Small free-tier models fail here in a particular way: not a wrong
  /// answer but token soup, several scripts deep, words repeating, no
  /// sentence anywhere in it. Seen on screen it reads as the app being
  /// broken rather than the model being cheap.
  ///
  /// Showing nothing is strictly better: the greeting stays, the card says it
  /// has nothing yet, and a tap tries again. So anything failing these tests
  /// is discarded rather than displayed.
  ///
  /// Deliberately blunt. These are not quality judgements — a dull line
  /// passes, and should: taste is what the prompt is for. This only catches
  /// output that no sentence in any language looks like.
  /// The checks that hold at any length: a stuck decoder, and a "word" no
  /// language has.
  ///
  /// Split out of [_plausible] because the rest of that method is calibrated
  /// for a single short line — "a word appearing three times is not writing"
  /// is true of a nine-word headline and false of any paragraph. A translation
  /// is a paragraph, so it gets these two and not the others.
  static String? _notGarbled(String? reply) {
    final text = reply?.trim();
    if (text == null || text.isEmpty) return null;
    // The same character four times over: a stuck decoder, never writing.
    if (RegExp(r'(.)\1{3,}').hasMatch(text)) return null;
    // Thirty letters with nothing between them is a decoder that stopped
    // emitting spaces. Letters specifically — a URL or a long file name in a
    // note is ordinary, and splitting on whitespace would have caught both.
    if (RegExp(r'\p{L}{31,}', unicode: true).hasMatch(text)) return null;
    return text;
  }

  static String? _plausible(String? reply) {
    final text = _notGarbled(reply);
    if (text == null) return null;

    var latin = 0;
    var arabic = 0;
    var foreign = 0;
    for (final rune in text.runes) {
      switch (rune) {
        case >= 0x0041 && <= 0x005A:
        case >= 0x0061 && <= 0x007A:
        case >= 0x00C0 && <= 0x024F:
          latin++;
        case >= 0x0600 && <= 0x06FF:
        case >= 0x0750 && <= 0x077F:
        case >= 0xFB50 && <= 0xFDFF:
        case >= 0xFE70 && <= 0xFEFF:
          arabic++;
        // Every other script with letters in it. One of these turning up in
        // a line meant to be English or Persian is not a loanword, it is the
        // decoder having lost its place.
        case >= 0x0370 && <= 0x05FF:
        case >= 0x0900 && <= 0x109F:
        case >= 0x1100 && <= 0x11FF:
        case >= 0x2E80 && <= 0x9FFF:
        case >= 0xAC00 && <= 0xD7AF:
          foreign++;
        default:
          break;
      }
    }
    if (latin + arabic + foreign == 0) return null;
    if (foreign > 1) return null;

    // A word repeating is the other shape these failures take — "toutes
    // toutes to". Two mentions is ordinary language; three of the same word
    // in a line this short is not.
    final words = [
      for (final word in text.toLowerCase().split(RegExp(r'[\s,.:;!?…]+')))
        if (word.length > 2) word,
    ];
    if (words.any((word) => word.length > 30)) return null;
    final counts = <String, int>{};
    for (final word in words) {
      final seen = (counts[word] ?? 0) + 1;
      if (seen > 2) return null;
      counts[word] = seen;
    }
    for (var i = 1; i < words.length; i++) {
      if (words[i] == words[i - 1]) return null;
    }
    return text;
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
    // Null means the request itself failed — non-200, timeout, unreadable
    // reply. That is absence, not an empty page: throwing keeps the note in
    // the backlog instead of permanently recording "no text found" over a
    // photo nobody ever actually looked at.
    if (reply == null) throw const AiUnavailableException();
    return OCRText(text: reply.trim());
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
      if (reply == null) throw const AiUnavailableException();
      return Transcript(text: reply.trim());
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
    if (streamed.statusCode != 200) {
      throw const AiUnavailableException();
    }
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
            // The key rides in the `x-goog-api-key` header (see [_headers]),
            // like every other provider's credential in its header. It used
            // to be a `?key=` query parameter — the quickstart form — but a
            // key in a URL is a key that shows up in proxy logs, server logs
            // and any diagnostics that print the request line.
            Uri.parse(
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
      if (response.statusCode != 200) {
        throw const AiUnavailableException();
      }
      final decoded = jsonDecode(_bodyText(response));
      // Spelled out rather than chained: `cond ? a?['b'] : c` puts a `?[` where
      // the parser is still expecting the ternary's true branch.
      if (decoded is! Map) throw const AiUnavailableException();
      final embedding = decoded['embedding'];
      if (embedding is! Map) throw const AiUnavailableException();
      final values = embedding['values'];
      if (values is! List) throw const AiUnavailableException();
      return Vector([for (final value in values) (value as num).toDouble()]);
    }
    final response = await _client
        .post(
          Uri.parse('${config.resolvedBaseUrl}/v1/embeddings'),
          headers: _headers,
          body: jsonEncode({'model': 'text-embedding-3-small', 'input': text}),
        )
        .timeout(_textTimeout);
    if (response.statusCode != 200) {
      throw const AiUnavailableException();
    }
    final decoded = jsonDecode(_bodyText(response));
    if (decoded is! Map<String, dynamic>) {
      throw const AiUnavailableException();
    }
    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw const AiUnavailableException();
    }
    final values = (data.first as Map)['embedding'];
    if (values is! List) throw const AiUnavailableException();
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
