import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:nex_core/nex_core.dart';

/// Phase 1's real [ChatAdapter]: an on-device model over LiteRT-LM
/// (09-ai.md — "Phase 1, re-planned on LiteRT-LM").
///
/// Replaces `PlaceholderLocalChatAdapter`, and replaces the llama.cpp runtime
/// Phase 0 pinned. That pin is why this took as long as it did: every
/// benchmark run against it measured a CPU build and was read as a property of
/// the phone, when the same device turned out to run a larger model roughly
/// ten times faster over OpenCL. The measurements were never wrong; they were
/// scoped to one path.
///
/// Nothing above this class changed to accommodate it. [ChatAdapter] was
/// written as a contract that does not know what implements it, and swapping
/// the entire inference stack underneath it touches this file and the
/// package's dependency list.
class LiteRtChatAdapter implements ChatAdapter {
  LiteRtChatAdapter({
    required String modelPath,
    this.preferGpu = true,
    @visibleForTesting LiteLmEngine? engine,
    @visibleForTesting
    Future<LiteLmEngine> Function(LiteLmEngineConfig config)? loadEngine,
  }) : _path = (() => modelPath),
       _engine = engine,
       _enginePath = engine == null ? null : modelPath,
       _loadEngine = loadEngine ?? LiteLmEngine.create;

  /// An adapter whose model can change while the app runs: [modelPath] is
  /// asked again before every load, and a loaded model that is no longer the
  /// one it names is released and the new one loaded in its place.
  LiteRtChatAdapter.following(
    String Function() modelPath, {
    this.preferGpu = true,
  }) : _path = modelPath,
       _loadEngine = LiteLmEngine.create;

  final String Function() _path;

  /// How an engine is brought up: the runtime's own loader, or a test's.
  final Future<LiteLmEngine> Function(LiteLmEngineConfig config) _loadEngine;

  /// Where the `.litertlm` weights live on disk.
  ///
  /// Supplied rather than discovered: the file is gigabytes and arrives
  /// through a download this package deliberately knows nothing about. A path
  /// that is not there yet is an ordinary state, not an error — see
  /// [available].
  String get modelPath => _path();

  /// The path [_engine] was loaded from.
  String? _enginePath;

  /// Try the GPU (OpenCL) backend first.
  ///
  /// The NPU backend is never used, on purpose. It is the fastest path on the
  /// hardware that has it, and on hardware that does not it can take the whole
  /// process down in native code rather than returning a failure Dart can
  /// catch. A chat feature is not worth a crash, so this ships GPU-then-CPU
  /// and leaves NPU to a device allowlist that does not exist yet.
  final bool preferGpu;

  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;

  /// How many messages of the caller's history the live conversation has
  /// already been told about — see [sendMessage] on why this is tracked.
  int _sentThroughIndex = 0;
  String? _systemInstruction;

  /// Content signature of what the live conversation has been told so far:
  /// the system instruction plus every turn through [_sentThroughIndex].
  ///
  /// Divergence used to be judged on counts alone — a resumed thread just had
  /// to be no *shorter* than what was sent before. The binding adapter is
  /// process-wide, so opening a second thread after closing a first one was
  /// judged a continuation whenever its history was at least as long: the
  /// tail of thread B arrived as a reply to a prefix from thread A, or — when
  /// the two were exactly equal — nothing new was pending at all and the
  /// adapter answered with an empty string. Comparing content, not counts,
  /// is what makes "a different conversation" detectable.
  int _sentSignature = 0;

  static int _signatureOf(String? system, List<ChatMessage> turns, int upTo) {
    var hash = system == null ? 0 : system.hashCode;
    for (var i = 0; i < upTo && i < turns.length; i++) {
      hash = Object.hash(hash, turns[i].role, turns[i].content);
    }
    return hash;
  }

  /// Whether this build can run a local model at all.
  ///
  /// Android and iOS only: the plugin registers no other platform. The GPU
  /// backend is Android-only on top of that, which [_backends] handles.
  static bool get supportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Whether there is a model on disk to answer with.
  @override
  bool get available =>
      supportedPlatform && modelPath.isNotEmpty && File(modelPath).existsSync();

  /// Backends to try, in order. GPU is Android-only; CPU is the floor
  /// everywhere and is always last, so there is always something left to fall
  /// back to rather than a failure the user cannot act on.
  List<LiteLmBackend> get _backends => [
    if (preferGpu && !kIsWeb && Platform.isAndroid) LiteLmBackend.gpu,
    LiteLmBackend.cpu,
  ];

  /// Loads the model now rather than inside the first question.
  ///
  /// Returns null when there is nothing to load — no weights on disk, or a
  /// platform with no runtime — so a caller can tell "already warm" from
  /// "there is a wait coming" without starting one.
  @override
  Future<void>? warmUp() {
    if (!available || (_engine != null && _enginePath == modelPath)) {
      return null;
    }
    return _ensureEngine().whenComplete(_settle);
  }

  /// How long a loaded model may sit unused before it is released.
  static const idleRelease = Duration(minutes: 5);

  Timer? _idle;
  int _inFlight = 0;

  /// Starts the idle clock again: used just now, released in [idleRelease]
  /// unless used again first.
  void _settle() {
    _idle?.cancel();
    _idle = Timer(idleRelease, () => unawaited(release()));
  }

  /// Unloads the model, unless a message is being answered — that one
  /// finishes, and the idle clock it restarts releases it later (PERF-02).
  @override
  Future<void>? release() {
    if (_engine == null || _inFlight > 0) return null;
    _idle?.cancel();
    _idle = null;
    return close();
  }

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    // Null *before* awaiting, the convention every AIAdapter method follows:
    // "unavailable" is a state the caller checks for, not an exception it
    // catches. With no model downloaded yet this is the whole answer.
    if (!available || history.isEmpty) return null;
    _inFlight++;
    return _send(withScopeCeiling(history)).whenComplete(() {
      _inFlight--;
      _settle();
    });
  }

  Future<ChatResponse> _send(List<ChatMessage> conversation) async {
    // The system message is taken off the transcript and written into the
    // start of the first user turn — see [withInstructions] for why not
    // LiteRT-LM's own `systemInstruction` slot.
    final system = conversation.first.role == ChatRole.system
        ? conversation.first.content
        : null;
    final turns = [
      for (final message in conversation)
        if (message.role != ChatRole.system) message,
    ];
    if (turns.isEmpty) {
      return const ChatResponse(content: '');
    }
    final prepared = withInstructions(system, turns);

    await _ensureConversation(system, turns, prepared);

    // Only the turns the live conversation has not seen. The contract hands
    // over the whole history every call, and replaying all of it would mean
    // re-running prefill over the entire transcript on every message — which
    // is the expensive half on this hardware, and grows with the conversation.
    // `_sentThroughIndex` is what lets an append-only history cost one turn.
    final pending = prepared.sublist(_sentThroughIndex.clamp(0, turns.length));
    final userTurns = [
      for (final turn in pending)
        if (turn.role == ChatRole.user) turn.content,
    ];
    if (userTurns.isEmpty) {
      // The last thing in the history is already an assistant turn — nothing
      // was asked. Better an empty answer than replaying the transcript to
      // manufacture one.
      return const ChatResponse(content: '');
    }

    LiteLmMessage? reply;
    for (final text in userTurns) {
      reply = await _conversation!.sendMessage(text);
    }
    _sentThroughIndex = turns.length;
    _sentSignature = _signatureOf(system, turns, _sentThroughIndex);
    return ChatResponse(content: reply?.text.trim() ?? '');
  }

  /// Brings up an engine and a conversation, reusing both when they still
  /// match what is being asked for.
  ///
  /// Loading is the expensive step — gigabytes off disk and onto the GPU — so
  /// it happens once per adapter rather than once per message. The
  /// conversation is rebuilt only when the caller's history stops being an
  /// extension of what this one has already been told: a resumed thread, a
  /// different conversation, or an edited transcript.
  Future<void> _ensureConversation(
    String? system,
    List<ChatMessage> turns,
    List<ChatMessage> prepared,
  ) async {
    final engine = await _ensureEngine();
    final diverged =
        _conversation == null ||
        system != _systemInstruction ||
        turns.length < _sentThroughIndex ||
        _sentSignature !=
            _signatureOf(
              system,
              turns,
              _sentThroughIndex.clamp(0, turns.length),
            );
    if (!diverged) return;

    await _conversation?.dispose();
    _systemInstruction = system;
    // Everything before the pending turns is replayed as history the model is
    // given rather than as messages it answers, which is what
    // `initialMessages` is for.
    final replay = prepared.length > 1
        ? prepared.sublist(0, prepared.length - 1)
        : const <ChatMessage>[];
    _conversation = await engine.createConversation(
      // No `systemInstruction`: the instructions ride the first user turn
      // instead — see [withInstructions].
      LiteLmConversationConfig(
        initialMessages: [
          for (final turn in replay)
            turn.role == ChatRole.assistant
                ? LiteLmMessage.model(turn.content)
                : LiteLmMessage.user(turn.content),
        ],
      ),
    );
    _sentThroughIndex = replay.length;
    _sentSignature = _signatureOf(system, turns, replay.length);
  }

  /// [turns] with [system] written into the start of the first user turn.
  ///
  /// Not LiteRT-LM's `systemInstruction`. Whether that slot reaches the
  /// model depends on the model's own chat template, and with Gemma 4 it
  /// did not: the assistant introduced itself as "Gemma, not Nex" and had
  /// never seen the notes it was asked about, though both were in the
  /// instruction it was given. Every template carries a user turn, so the
  /// instructions go there — once, at the start of the conversation, and
  /// marked as the app's rather than the person's words.
  @visibleForTesting
  static List<ChatMessage> withInstructions(
    String? system,
    List<ChatMessage> turns,
  ) {
    if (system == null || system.trim().isEmpty) return turns;
    final first = turns.indexWhere((turn) => turn.role == ChatRole.user);
    if (first < 0) return turns;
    return [
      for (var i = 0; i < turns.length; i++)
        if (i == first)
          ChatMessage(
            role: ChatRole.user,
            content:
                '[Instructions from the Nex app — not written by the user]\n'
                '${system.trim()}\n'
                '[End of instructions. The user says:]\n'
                '${turns[i].content}',
          )
        else
          turns[i],
    ];
  }

  /// A note on disk saying "a backend load is in progress".
  ///
  /// Loading a model is native work, and native work does not fail politely:
  /// on the wrong file or the wrong driver it aborts the process, which no
  /// `try` in Dart can catch. Without a record that survives the crash, the
  /// next launch tries the same backend and dies the same way — the app
  /// becomes unopenable by the one action the user most wants to repeat.
  ///
  /// So the attempt is written down *before* it happens and cleared after.
  ///
  /// One line per backend: its name, how many loads in a row never came
  /// back, and when the last one started. This used to be the name alone,
  /// and one unfinished load was enough to skip that backend *for good* —
  /// but a load also never comes back when the app is swiped away, or when
  /// Android reclaims it mid-load, which on a phone loading two gigabytes is
  /// ordinary. Once both backends had been unlucky once, the model never
  /// loaded again and "try again" could not change that: the error a person
  /// saw on every message. Now a backend is skipped only after [maxStrikes]
  /// loads in a row that took the process with them, and only for
  /// [strikeExpiry]: a phone that was short of memory once is not barred
  /// for ever.
  File get _attemptMarker => File('$modelPath.loading');

  /// Unfinished loads in a row before a backend is skipped.
  static const maxStrikes = 2;

  /// How long a skipped backend stays skipped before it is tried again.
  static const strikeExpiry = Duration(hours: 12);

  /// Backend name → (unfinished loads in a row, when the last one started),
  /// leaving out entries older than [strikeExpiry]. A line in the old format
  /// — a bare name — counts as one strike as of the file's own date, so an
  /// install stuck under the old rule gets its backends back.
  Map<String, (int, DateTime)> _strikes() {
    try {
      final file = _attemptMarker;
      if (!file.existsSync()) return {};
      final now = DateTime.now();
      final written = file.lastModifiedSync();
      final strikes = <String, (int, DateTime)>{};
      for (final raw in file.readAsLinesSync()) {
        final fields = raw.trim().split(' ');
        if (fields.first.isEmpty) continue;
        final count = fields.length > 1 ? int.tryParse(fields[1]) ?? 1 : 1;
        final at = fields.length > 2
            ? DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(fields[2]) ?? written.millisecondsSinceEpoch,
              )
            : written;
        if (now.difference(at) > strikeExpiry) continue;
        strikes[fields.first] = (count, at);
      }
      return strikes;
    } catch (_) {
      return {};
    }
  }

  void _writeStrikes(Map<String, (int, DateTime)> strikes) {
    try {
      if (strikes.isEmpty) {
        if (_attemptMarker.existsSync()) _attemptMarker.deleteSync();
        return;
      }
      _attemptMarker.writeAsStringSync(
        [
          for (final MapEntry(:key, value: (count, at)) in strikes.entries)
            '$key $count ${at.millisecondsSinceEpoch}',
        ].join('\n'),
        flush: true,
      );
    } catch (_) {
      // An unwritable directory costs the protection, not the feature.
    }
  }

  void _recordAttempt(LiteLmBackend backend) {
    final strikes = _strikes();
    final (count, _) = strikes[backend.name] ?? (0, DateTime.now());
    strikes[backend.name] = (count + 1, DateTime.now());
    _writeStrikes(strikes);
  }

  void _clearAttempt(LiteLmBackend backend) =>
      _writeStrikes(_strikes()..remove(backend.name));

  /// The engine being brought up, while one is. Every caller in that time
  /// waits for it instead of starting a load of its own.
  ///
  /// Without this, opening the assistant (which warms the model up) and
  /// sending a message — or the smart summary asking at the same moment —
  /// each loaded the model, and two copies of two gigabytes do not fit on a
  /// phone: Android ended the app mid-load, which also left the marker
  /// above behind.
  Future<LiteLmEngine>? _loading;
  String? _loadingPath;

  @visibleForTesting
  Future<LiteLmEngine> ensureEngine() => _ensureEngine();

  Future<LiteLmEngine> _ensureEngine() {
    final path = modelPath;
    final existing = _engine;
    if (existing != null && _enginePath == path) return Future.value(existing);
    final pending = _loading;
    if (pending != null && _loadingPath == path) return pending;
    final load = _loadAfter(pending, path);
    _loading = load;
    _loadingPath = path;
    return load.whenComplete(() {
      if (identical(_loading, load)) {
        _loading = null;
        _loadingPath = null;
      }
    });
  }

  /// Loads [path] once [before] — a load of a different model — has
  /// settled, so the two are never in memory together.
  Future<LiteLmEngine> _loadAfter(
    Future<LiteLmEngine>? before,
    String path,
  ) async {
    if (before != null) {
      try {
        await before;
      } catch (_) {}
    }
    final existing = _engine;
    if (existing != null && _enginePath == path) return existing;
    // Another model was picked since this one loaded: two sets of weights
    // will not fit in memory together, so the old one goes first.
    if (existing != null) await close();

    final strikes = _strikes();
    Object? lastFailure;
    for (final backend in _backends) {
      final (count, _) = strikes[backend.name] ?? (0, DateTime.now());
      if (count >= maxStrikes) {
        // Tried and never came back, more than once and recently. Skipping
        // it is the difference between an app that starts and one that
        // does not.
        lastFailure = StateError(
          '${backend.name} did not finish loading $count times in a row',
        );
        continue;
      }
      _recordAttempt(backend);
      try {
        final engine = await _loadEngine(
          LiteLmEngineConfig(modelPath: path, backend: backend),
        );
        _clearAttempt(backend);
        _engine = engine;
        _enginePath = path;
        return engine;
      } catch (error) {
        // A device that reports OpenCL and still fails to bring up the GPU
        // backend is common enough to plan for rather than to surface. A
        // *caught* failure is not a crash, so the marker comes off: the
        // backend behaved, it just could not load this file.
        _clearAttempt(backend);
        lastFailure = error;
      }
    }
    throw StateError('No LiteRT-LM backend could load $path: $lastFailure');
  }

  /// Releases the model. Worth calling: the weights are the largest single
  /// allocation this app ever makes, and Android reclaims the process rather
  /// than asking twice.
  Future<void> close() async {
    await _conversation?.dispose();
    await _engine?.dispose();
    _conversation = null;
    _engine = null;
    _enginePath = null;
    _sentThroughIndex = 0;
    _sentSignature = 0;
    _systemInstruction = null;
  }
}
