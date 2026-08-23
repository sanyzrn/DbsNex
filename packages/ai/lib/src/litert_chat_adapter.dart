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
    required this.modelPath,
    this.preferGpu = true,
    @visibleForTesting LiteLmEngine? engine,
  }) : _engine = engine;

  /// Where the `.litertlm` weights live on disk.
  ///
  /// Supplied rather than discovered: the file is ~2.6 GB and arrives through
  /// a download this package deliberately knows nothing about. A path that is
  /// not there yet is an ordinary state, not an error — see [available].
  final String modelPath;

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
    if (!available || _engine != null) return null;
    return _ensureEngine();
  }

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    // Null *before* awaiting, the convention every AIAdapter method follows:
    // "unavailable" is a state the caller checks for, not an exception it
    // catches. With no model downloaded yet this is the whole answer.
    if (!available || history.isEmpty) return null;
    return _send(withScopeCeiling(history));
  }

  Future<ChatResponse> _send(List<ChatMessage> conversation) async {
    // The system message becomes LiteRT-LM's `systemInstruction` rather than a
    // turn in the transcript. It is not something the user said, and models
    // weight it differently when it arrives in the slot meant for it.
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

    await _ensureConversation(system, turns);

    // Only the turns the live conversation has not seen. The contract hands
    // over the whole history every call, and replaying all of it would mean
    // re-running prefill over the entire transcript on every message — which
    // is the expensive half on this hardware, and grows with the conversation.
    // `_sentThroughIndex` is what lets an append-only history cost one turn.
    final pending = turns.sublist(_sentThroughIndex.clamp(0, turns.length));
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
  ) async {
    final engine = await _ensureEngine();
    final diverged =
        _conversation == null ||
        system != _systemInstruction ||
        turns.length < _sentThroughIndex;
    if (!diverged) return;

    await _conversation?.dispose();
    _systemInstruction = system;
    // Everything before the pending turns is replayed as history the model is
    // given rather than as messages it answers, which is what
    // `initialMessages` is for.
    final replay = turns.length > 1
        ? turns.sublist(0, turns.length - 1)
        : const <ChatMessage>[];
    _conversation = await engine.createConversation(
      LiteLmConversationConfig(
        systemInstruction: system,
        initialMessages: [
          for (final turn in replay)
            turn.role == ChatRole.assistant
                ? LiteLmMessage.model(turn.content)
                : LiteLmMessage.user(turn.content),
        ],
      ),
    );
    _sentThroughIndex = replay.length;
  }

  Future<LiteLmEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;

    Object? lastFailure;
    for (final backend in _backends) {
      try {
        final engine = await LiteLmEngine.create(
          LiteLmEngineConfig(modelPath: modelPath, backend: backend),
        );
        _engine = engine;
        return engine;
      } catch (error) {
        // A device that reports OpenCL and still fails to bring up the GPU
        // backend is common enough to plan for rather than to surface. The
        // loop moves on to CPU; only running out of backends is a real error.
        lastFailure = error;
      }
    }
    throw StateError(
      'No LiteRT-LM backend could load $modelPath: $lastFailure',
    );
  }

  /// Releases the model. Worth calling: the weights are the largest single
  /// allocation this app ever makes, and Android reclaims the process rather
  /// than asking twice.
  Future<void> close() async {
    await _conversation?.dispose();
    await _engine?.dispose();
    _conversation = null;
    _engine = null;
    _sentThroughIndex = 0;
    _systemInstruction = null;
  }
}
