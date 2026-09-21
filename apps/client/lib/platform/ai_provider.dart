import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
  ///
  /// OpenRouter is deliberately not on this list, by the same rule
  /// [hearsAudio] states one line up: unavailable beats a wrong answer. It
  /// routes chat completions across many models, and `_embed` asks for one
  /// specific OpenAI embedding model by name — nothing makes that model
  /// reachable through the router. Claiming the capability turned that into
  /// a request that fails when somebody searches, rather than a feature that
  /// says up front it is not offered here, which is what FR-8b.4 asks for.
  ///
  /// Custom stays: its endpoint is one the user chose and declared
  /// OpenAI-shaped, and the app has no way to know better than they do.
  bool get embeds =>
      this == AiProvider.openai ||
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

  /// The model this provider's embeddings actually come from.
  ///
  /// Not [model]: that is the *chat* model, and the embedding endpoint takes
  /// its own. Spelled here rather than at the call site so the literal
  /// appears once — `_embed` sends it, and the embedding-space fingerprint
  /// is built from it, and those two must never be able to disagree about
  /// which space the stored vectors belong to.
  String get embeddingModel => switch (provider.format) {
    AiWireFormat.gemini => 'text-embedding-004',
    _ => 'text-embedding-3-small',
  };

  /// What decides whether two sets of stored vectors are comparable.
  ///
  /// The endpoint as well as the model, because the same model name behind a
  /// different base URL is not a promise of the same vectors — a
  /// self-hosted or proxied endpoint is free to serve something else
  /// entirely under a familiar name.
  String get embeddingSpace =>
      '${provider.wireName}|$resolvedBaseUrl|$embeddingModel';

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

/// What the daily brief is — a question with more than one right answer, and
/// until now only one of them was on offer.
///
/// The five differ in exactly one thing: how much of the brief the model
/// writes. Everything else — the facts underneath, the line budget, the
/// tidying on the way out — is shared, because those are the parts that were
/// never in dispute.
///
/// The ladder runs from all of it to none of it. [assistant] is the original
/// and stays the default, so nobody who liked it has to do anything.
/// [blended] and [planner] state the facts from the app's own records and
/// spend the model on the one line it is actually better at. [report] asks
/// nothing of anyone, which is why it is the only one that works with no
/// provider, no key and no network. [custom] is the preset you write
/// yourself.
enum NexBriefStyle {
  /// Everything goes to the model; up to [NexBriefLength.lines] come back.
  assistant('assistant'),

  /// The app writes what is true, the model adds one observation.
  blended('blended'),

  /// The app writes what is true and stops. No request is made.
  report('report'),

  /// The app writes what is true, the model suggests one next step.
  planner('planner'),

  /// The user's own instruction, in place of a preset's.
  custom('custom');

  const NexBriefStyle(this.wireName);

  final String wireName;

  /// Whether a provider is asked for anything at all.
  ///
  /// False is not a degraded mode. It is the one setting under which the
  /// brief cannot be wrong about a date, cannot cost anything, and cannot
  /// fail to appear because a plane is in the air.
  bool get usesModel => this != NexBriefStyle.report;

  /// Whether the app states the facts itself and the model, if any, writes
  /// only what is left.
  ///
  /// [assistant] and [custom] are the two that hand the whole set over: the
  /// first because that is what it has always been, the second because a
  /// person who has written their own instruction has asked for their own
  /// instruction, not for ours wrapped around it.
  bool get statesFacts =>
      this == NexBriefStyle.blended ||
      this == NexBriefStyle.report ||
      this == NexBriefStyle.planner;

  static NexBriefStyle fromWire(String? value) =>
      NexBriefStyle.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => NexBriefStyle.assistant,
      );
}

/// How much of the card a brief is allowed to fill.
///
/// A line count rather than a token budget, which is what makes this a
/// different quantity from [AiAnswerLength]: an answer is as long as the
/// question needs, a brief is as long as there are things waiting. The
/// budget is stated to the model *and* enforced by `nexTidyBrief` on the way
/// back, for the same reason as everywhere else here — "at most" is a
/// suggestion to a model and arithmetic to a tidier.
///
/// Still a ceiling, never a target. A day with one thing on it gets one line
/// under all three.
enum NexBriefLength {
  short('short', 2),
  medium('medium', 4),
  long('long', 6);

  const NexBriefLength(this.wireName, this.lines);

  final String wireName;

  /// The most lines the whole brief may have, the app's own included.
  final int lines;

  static NexBriefLength fromWire(String? value) =>
      NexBriefLength.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => NexBriefLength.medium,
      );
}

/// A file the question is about, sent with it.
///
/// The assistant could always read what was *typed* into a note and never
/// what was attached to one — so "what does this receipt say?" about a photo
/// sitting right there on the screen got "I cannot see images", which is true
/// of the text in the prompt and false of the app.
///
/// Bytes rather than a path: the adapter has no business touching the media
/// directory, and the caller has already decided this one is worth sending.
@immutable
class NexChatAttachment {
  const NexChatAttachment({required this.bytes, required this.mimeType});

  /// `List<int>` rather than `Uint8List`: everything that produces these —
  /// `readAsBytesSync`, a picker, a test — hands over something that is
  /// already one, and `base64Encode` takes the wider type anyway.
  final List<int> bytes;
  final String mimeType;
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
    this.attachments = const [],
    this.userName = '',
    this.userIntroduction = '',
    this.now,
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

  /// Images the question is about, sent with the newest question.
  ///
  /// Re-sent on every turn rather than once, which costs tokens and is the
  /// right trade: a photo the first question was about is what the third
  /// follow-up is about too, and a model that has forgotten it answers the
  /// follow-up by inventing.
  final List<NexChatAttachment> attachments;

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

  /// What time it is where the user is.
  ///
  /// Load-bearing only once the assistant could set a reminder, and then
  /// completely: "remind me Friday at nine" cannot be turned into a date by
  /// something that does not know what day it is today. A model with no
  /// clock either refuses, or — the failure this exists to prevent — picks a
  /// date out of its training data and sets an alarm for a day in the past.
  ///
  /// Injectable so the prompt is testable. Null means now.
  final DateTime? now;

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
  }) : _client = client ?? _defaultClient(),
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

  /// The budget for what the app asks for without being asked: the recap and
  /// the headline, which draw themselves on launch.
  ///
  /// Nobody is waiting on these the way they wait on an answer they typed a
  /// question for, and they are the wrong thing to spend ninety seconds of
  /// spinner on. A card that gives up at twenty seconds and leaves yesterday's
  /// recap in place is a card that works; the same card still spinning a
  /// minute and a half after launch is an app that looks broken.
  static const ambientTimeout = Duration(seconds: 20);

  /// How long a connection may take to establish, as opposed to answer.
  ///
  /// The case this is for is a network that is joined but not connected — the
  /// hotel Wi-Fi nobody paid for, the office VLAN with no route out. DNS
  /// answers, the socket opens, and nothing ever comes back. Without this the
  /// wait is the platform's own, which on Android runs into minutes, and every
  /// request the app makes on launch waits it out.
  static const connectTimeout = Duration(seconds: 8);

  static http.Client _defaultClient() =>
      IOClient(HttpClient()..connectionTimeout = connectTimeout);

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
    Duration? timeout,
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
        .timeout(timeout ?? (media == null ? _textTimeout : _mediaTimeout));
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

  /// One sentence about a piece of text that is not (yet) a note.
  ///
  /// The bookmark path has a page's title and excerpt in hand and wants the
  /// same one-line summary [summarize] gives a note. It used to call
  /// [digest] for it, which was always a slight misfit and became a plain
  /// bug when the brief became a list: a saved link would have come back
  /// described as an emoji-led reminder of something waiting on you.
  ///
  /// Null rather than an empty [Summary], because the one caller's question
  /// is "is there a sentence to store".
  Future<String?> summarizeText(String text) async {
    if (!canAnswerText || text.trim().isEmpty) return null;
    final summary = await _summarize(text);
    return summary.text.isEmpty ? null : summary.text;
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

  /// The recap the timeline shows when the app is opened.
  ///
  /// Not part of [AIAdapter]: every other capability there takes one [Note],
  /// because enrichment is a per-note pipeline. This is the one place in the
  /// app that wants "here is the state of somebody's library, say what is in
  /// it" rather than "extract something from this one" — it belongs to the
  /// timeline's own daily-summary panel, not to the note-scoped contract.
  ///
  /// What it is *for* changed. It used to be an observation about what
  /// someone had been writing lately, which is a second decorative line in an
  /// app that already has one above it — the headline. Its job now is to put
  /// them back in touch with their own notes: what is due, what is
  /// unfinished, what they were in the middle of. That only became possible
  /// once [nexRecapSource] started sending facts instead of prose; with only
  /// note text to go on, a model asked to remind someone of something
  /// invents it.
  ///
  /// Hence the sentence forbidding invention, which is new and load-bearing.
  /// A wrong joke about your notes is a bad line. A wrong claim that
  /// something is due tomorrow is a missed appointment.
  ///
  /// Its *shape* changed with it. It is a short list now, not a paragraph:
  /// one thing per line, each led by an emoji, overdue first. Somebody
  /// opening a notes app in the morning is checking whether anything needs
  /// them, and prose makes them read the whole thing to find out.
  ///
  /// [lines] is stated in the prompt *and* enforced on the way out by
  /// [nexTidyBrief], because models treat "at most" as a suggestion and
  /// reach for a bullet or a heading the moment they are asked for a list.
  /// Asking every model this app talks to — the small ones on the phone
  /// included — to behave every time is a wish; the tidier is arithmetic.
  ///
  /// [style] decides how much of the brief this method is responsible for at
  /// all. Under [NexBriefStyle.assistant] it is the whole thing, which is
  /// what it has always been; under the two that state their own facts it is
  /// a single line, and [written] carries the lines the app has already
  /// prepared so that the model can be told not to say them again. Under
  /// [NexBriefStyle.report] this is never called.
  Future<String?> digest(
    String recentNotesText, {
    int lines = 3,
    Duration? timeout,
    NexBriefStyle style = NexBriefStyle.assistant,
    AiResponseStyle tone = AiResponseStyle.natural,
    String instruction = '',
    String written = '',
  }) async {
    if (!canAnswerText || recentNotesText.trim().isEmpty) return null;
    if (style != NexBriefStyle.assistant) {
      return _sideBrief(
        recentNotesText,
        style: style,
        tone: tone,
        instruction: instruction,
        written: written,
        lines: lines,
        timeout: timeout,
      );
    }
    final reply = await _complete(
      'You are the assistant in a notes app, telling someone what is waiting '
      'on them. Not a summary of their week — a short list of the things '
      'they would want to be reminded of, in the order they matter. '
      // The shape is described rather than left to be inferred: these lines
      // are abbreviated to save tokens, and an abbreviation a model has to
      // guess at is one it will eventually guess wrong.
      'Each line you are given is one note, written as `when | kind | text`. '
      'A line starting DUE carries a reminder — "DUE in 6h", "DUE overdue '
      '2d" — and those lines come first; the rest are newest first. On a '
      'checklist, "3/5 left" means three of its five items are still '
      'unticked. A middle column reading "every month", "every 2h" and so on '
      'is a standing commitment rather than a note — a bill, a renewal, a '
      'tablet — and "3 of 7 today" is how many times it has been done today. '
      'Say those the way somebody would: "the rent is due on Friday", not '
      '"you have a monthly commitment". '
      'Answer with at most $lines lines. One thing per line, each beginning '
      'with a single emoji that fits it, then a short sentence. Overdue '
      'first, then what is due soon, then what is unfinished, then anything '
      'worth being reminded of. Say what to do where there is something to '
      'do: "Call the plumber — overdue by two days", not "you have an '
      'overdue reminder". Name the real things, not the categories they '
      'belong to — "the cooler and the plane tickets", not "errands and '
      'travel plans". '
      // The half this used to forbid outright, and the reason the recap read
      // as a list of what somebody already knew. "No advice" is the right
      // rule about facts and the wrong rule about relationships: the model
      // sees the whole set at once, which is the one thing the reader does
      // not, and a clash between two of these lines is invisible from inside
      // either of them.
      'One of your lines may be something you noticed rather than something '
      'on the list. Worth noticing: two things due within an hour of each '
      'other, a reminder overdue so long it is worth moving or dropping, the '
      'same task written twice, a standing commitment usually done by now '
      'that is not, a checklist nothing has been ticked on in a week. Say it '
      'plainly and say what it means — "the dentist and the school run are '
      'both at 3" — and put it where it belongs in the order, not always '
      'last. '
      'Fewer lines when there is less: if only one thing is waiting, answer '
      'with one line. Never pad to the limit, and never manufacture an '
      'observation to fill one — if nothing about the set is worth saying, '
      'say nothing about the set. '
      'The tone is somebody who has read your notes and is telling you what '
      'is in them: dry, warm, plain. Never motivational, never corporate, '
      'never flattering, no questions. '
      // Sharpened, not relaxed. The rule that matters is about facts and it
      // is the same rule as before: a wrong claim that something is due
      // tomorrow is a missed appointment. What changed is that it now says
      // which half it governs — "never state anything that is not in the
      // lines" also forbade "these two are at the same time", which is not a
      // new fact but two old ones read together.
      'Every fact must come from the lines you were given: no invented dates, '
      'times, tasks or names. Reading two lines together is not inventing; '
      'asserting a third thing is. If you are not certain two lines really do '
      'clash, leave it out. '
      'No preamble, no heading, no bullet or number in front of a line, no '
      'quotes, no markdown. One emoji per line and never more. Write in one '
      'language only. '
      'Reply with the lines only. ${outputLanguage.promptRule}',
      recentNotesText,
      // Room for the whole budget and then some, because a reply cut off by
      // the token ceiling ends mid-word and the tidier cannot tell that from
      // a model that simply stopped.
      maxTokens: (lines * 60).clamp(200, 800),
      timeout: timeout,
    );
    // Line-aware, unlike the word clamp this replaced: that one collapsed
    // every run of whitespace in the reply, newlines included, which turned
    // a list back into the paragraph it was asked not to be.
    return _plausible(nexTidyBrief(reply, maxLines: lines), shortLine: false);
  }

  /// The model's share of a brief whose facts the app has already written.
  ///
  /// Every style but [NexBriefStyle.assistant] comes through here, and what
  /// they have in common is the thing that makes them worth having: the dates
  /// and the counts are not up for negotiation, because they were not asked
  /// for. What is asked for is the part arithmetic cannot do.
  ///
  /// So the budget is one line, not four, under all of them. A model given
  /// room for four lines beside four lines it has been told not to repeat
  /// will fill the room — with the same facts in other words, which is the
  /// exact failure these styles exist to avoid.
  Future<String?> _sideBrief(
    String recentNotesText, {
    required NexBriefStyle style,
    required AiResponseStyle tone,
    required String instruction,
    required String written,
    required int lines,
    Duration? timeout,
  }) async {
    // Under a custom instruction the user's sentence is the whole brief, so
    // the budget is theirs too. The other two get one line each.
    final budget = style == NexBriefStyle.custom ? lines : 1;
    final task = switch (style) {
      NexBriefStyle.blended =>
        'Write the one thing about this set that can only be seen by looking '
            'at all of it at once, and nothing else. Worth saying: two things '
            'due within an hour of each other, a reminder overdue so long it '
            'is worth moving or dropping, the same task written twice, a '
            'standing commitment usually done by now that is not, a checklist '
            'nothing has been ticked on in a week. Not worth saying: anything '
            'that is already one of the lines below, in any wording.',
      NexBriefStyle.planner =>
        'Suggest one thing to do next, and say in the same breath why it is '
            'that one — what it unblocks, what it is a prerequisite for, why '
            'it beats the others today. One suggestion, never a list. You are '
            'proposing, not deciding: never say anything has been done, '
            'moved, rescheduled or ticked, because nothing has.',
      NexBriefStyle.custom =>
        'The person reading this wrote the instruction below, in their own '
            'words, for what they want their daily brief to be. Follow it. '
            'Where it does not say, fall back on telling them plainly what is '
            'waiting on them.\n\nTheir instruction: $instruction',
      // Unreachable: `report` never asks anybody anything, and `assistant`
      // is answered above. Both are written out rather than defaulted so
      // that a sixth style cannot be added without this switch objecting.
      NexBriefStyle.assistant || NexBriefStyle.report => '',
    };
    if (task.isEmpty) return null;

    final reply = await _complete(
      'You are the assistant in a notes app. '
      '$task '
      // The same key as the whole-brief prompt above, because the lines
      // handed over are the same lines.
      'Each line you are given is one note or one standing commitment, '
      'written as `when | kind | text`. A line starting DUE carries a '
      'reminder — "DUE in 6h", "DUE overdue 2d". On a checklist, "3/5 left" '
      'means three of its five items are still unticked. '
      '${written.trim().isEmpty ? '' : 'These lines are already written and '
          'will be shown to the reader above yours. Do not repeat them and '
          'do not restate what they say:\n$written\n'}'
      'Answer with at most $budget '
      '${budget == 1 ? 'line' : 'lines'}, beginning with a single emoji that '
      'fits. '
      // The escape hatch, and it is not a formality: on a quiet, tidy day
      // there is genuinely no observation to make, and a manufactured one is
      // worse than none — it is the line that teaches people to stop reading
      // the card.
      'If there is nothing worth saying, reply with nothing at all rather '
      'than filling the space. '
      '${tone.promptRule} '
      // Identical to the whole-brief rules, deliberately word for word: a
      // brief that may invent a date under one setting and not another is a
      // brief nobody can trust under any of them.
      'Every fact must come from the lines you were given: no invented dates, '
      'times, tasks or names. Reading two lines together is not inventing; '
      'asserting a third thing is. If you are not certain, leave it out. '
      'No preamble, no heading, no bullet or number in front of a line, no '
      'quotes, no markdown. One emoji per line and never more. Write in one '
      'language only. '
      'Reply with the lines only. ${outputLanguage.promptRule}',
      recentNotesText,
      maxTokens: (budget * 60).clamp(120, 800),
      timeout: timeout,
    );
    return _plausible(
      nexTidyBrief(reply, maxLines: budget),
      shortLine: false,
    );
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
    Duration? timeout,
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
      timeout: timeout,
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

  /// One note, edited — the whole of it in, the whole of it back.
  ///
  /// What each style means and what it is forbidden from doing lives in
  /// [NexRewriteStyle]; this is only the call. Null on anything that is not an
  /// answer, the same as every other request here: the editor keeps what the
  /// person had and says the rewrite did not happen.
  ///
  /// The token ceiling is generous in both directions. A rewrite is roughly
  /// the length of its source, and a ceiling that clips one ends mid-sentence
  /// in somebody's note — which is worse than no answer, because it looks like
  /// an answer.
  Future<String?> rewrite(String text, {required NexRewriteStyle style}) async {
    final source = text.trim();
    if (!canAnswerText || source.isEmpty) return null;
    final reply = await _complete(
      style.prompt,
      source,
      maxTokens: math.min(4000, 300 + source.length),
      // A person is watching this one and waiting on it, so it gets the full
      // budget rather than the ambient one.
    );
    final edited = reply?.trim();
    if (edited == null || edited.isEmpty) return null;
    return _notGarbled(edited);
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
      // Its own rule, because "no preamble" was not reading as one. Every
      // reply opened with a greeting — "Hi!", "سلام!", "Of course!" — which
      // is preamble, but a model weighing that against the warmth rule below
      // resolves the tie in favour of being friendly. Naming the habit is
      // what settles it.
      'Never open with a greeting, an acknowledgement or a restatement — not '
          '"Hi", not "Of course", not "Great question", not "Let me check". '
          'The first words of every reply are the answer itself. The person '
          'is mid-conversation with their own notes, not being met at a door.',
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
    if (options.canAct) {
      parts.add(assistantActionPrompt);
      // Right after the protocol, because it is what makes one line of it
      // usable: `remind` asks for a concrete local date, and a model with no
      // clock cannot turn "Friday" into one. ISO with a weekday, because the
      // weekday is half of what people say and deriving it from the date is
      // arithmetic no model should have to be right about.
      parts.add(
        'It is now ${_nowLine(options.now ?? DateTime.now())}. Every date '
        'you send must be worked out from this, and must be in the future.',
      );
    }
    // Said outright, because the rule above it would otherwise argue against
    // the picture in the same request. "Answer only from the user's notes" is
    // exactly the sentence a model reaches for when it decides an attached
    // image is something from outside and refuses to look — which is the
    // refusal this whole path exists to end.
    if (options.attachments.isNotEmpty) {
      parts.add(
        'The image or images attached to the newest message are the pictures '
        'on the note being asked about. They are the notes, not something '
        'from outside them: look at them and answer from what you see. Never '
        'say you cannot see an image that has been attached.',
      );
    }
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

  /// The clock line, as `2026-03-12T14:05, a Thursday`.
  ///
  /// Local, never UTC: every reminder in this app is set in the time the
  /// person is standing in, and a prompt that said 11:05Z would have the
  /// model doing zone arithmetic it has no way to get right.
  static String _nowLine(DateTime now) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${now.year}-${two(now.month)}-${two(now.day)}'
        'T${two(now.hour)}:${two(now.minute)}';
    return '$date, a ${days[now.weekday - 1]}';
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
    // Only what the provider can actually look at. Sending an image to a
    // text-only model is a request that fails on the wire and reads to the
    // user as the assistant refusing, which is the bug this feature exists
    // to fix rather than a new shape of it.
    final media = config.provider.readsImages
        ? options.attachments
        : const <NexChatAttachment>[];
    // Attached to the newest question rather than to the turn that first
    // mentioned it: that is the turn every provider treats as the one being
    // answered.
    final attachTo = media.isEmpty
        ? -1
        : turns.lastIndexWhere((turn) => turn.role != ChatRole.assistant);

    final body = switch (config.provider.format) {
      AiWireFormat.anthropic => {
        'model': config.resolvedModel,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'system': system,
        'messages': [
          for (final (index, turn) in turns.indexed)
            {
              'role': turn.role == ChatRole.assistant ? 'assistant' : 'user',
              'content': index != attachTo
                  ? turn.content
                  : [
                      for (final file in media)
                        {
                          'type': 'image',
                          'source': {
                            'type': 'base64',
                            'media_type': file.mimeType,
                            'data': base64Encode(file.bytes),
                          },
                        },
                      {'type': 'text', 'text': turn.content},
                    ],
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
          for (final (index, turn) in turns.indexed)
            {
              'role': turn.role == ChatRole.assistant ? 'model' : 'user',
              'parts': [
                if (index == attachTo)
                  for (final file in media)
                    {
                      'inline_data': {
                        'mime_type': file.mimeType,
                        'data': base64Encode(file.bytes),
                      },
                    },
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
          for (final (index, turn) in turns.indexed)
            {
              'role': turn.role == ChatRole.assistant ? 'assistant' : 'user',
              'content': index != attachTo
                  ? turn.content
                  : [
                      {'type': 'text', 'text': turn.content},
                      for (final file in media)
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:${file.mimeType};base64,'
                                '${base64Encode(file.bytes)}',
                          },
                        },
                    ],
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

  /// [shortLine] is what the frequency check below is calibrated for, and it
  /// is off for anything longer than a line.
  static String? _plausible(String? reply, {bool shortLine = true}) {
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

    final words = [
      for (final word in text.toLowerCase().split(RegExp(r'[\s,.:;!?…]+')))
        if (word.length > 2) word,
    ];
    if (words.any((word) => word.length > 30)) return null;

    // A word repeating is the other shape these failures take — "toutes
    // toutes to". Two mentions is ordinary language; three of the same word
    // in a line this short is not.
    //
    // "This short" is the whole of it, which is why this is now behind a
    // flag instead of a threshold. The recap grew from thirty words to
    // eighty-five, and a frequency rule does not survive being scaled: "the"
    // is six per cent of ordinary English and thirty of a deliberately dry
    // sentence, so any ratio loose enough to keep real prose is loose enough
    // to catch nothing. Scaling it would have meant a card that goes blank
    // precisely on the days it has most to report.
    //
    // The headline is what this was written for and is unchanged. Longer
    // replies are carried by the checks that do not care about length: a
    // second script, a stuck decoder, a "word" no language has — and the
    // same word twice in a row, just below, which is the sharp end of this
    // one and stays absolute.
    if (shortLine) {
      final counts = <String, int>{};
      for (final word in words) {
        final seen = (counts[word] ?? 0) + 1;
        if (seen > 2) return null;
        counts[word] = seen;
      }
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
              '/v1beta/models/${config.embeddingModel}:embedContent',
            ),
            headers: _headers,
            body: jsonEncode({
              'model': 'models/${config.embeddingModel}',
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
          body: jsonEncode({
            'model': config.embeddingModel,
            'input': text,
          }),
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
