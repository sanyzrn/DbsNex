import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Phase 0 of the offline-AI roadmap (docs/09-ai.md): a throwaway harness
/// that answers one question — does a local GGUF model run at all on this
/// device, and how fast — before anything is built on top of it.
///
/// This is deliberately not the shape of the eventual `AIAdapter`
/// implementation. It has no capability gating, no tool-calling, no memory;
/// it loads one model and times one prompt at a time. Its only caller is
/// `apps/client/lib/dev/local_ai_bench_main.dart`, a standalone entry point
/// `main.dart` never imports — deleting this class must not touch the
/// shipped app.
class NexLocalBenchEngine {
  NexLocalBenchEngine._(this._engine, this._chat);

  final LlamaEngine _engine;
  final EngineChat _chat;

  /// Loads [modelPath] (a `.gguf` file already on disk — Phase 0 has no
  /// download UI yet, see the dev README) and starts a chat session.
  ///
  /// [libraryPath] is the llama.cpp shared library itself, not the model.
  /// On Android it resolves by basename once `libllama.so` is unpacked from
  /// the AAR into the app's native library directory — see
  /// `android/app/build.gradle.kts` and `android/app/libs/README.md`.
  static Future<NexLocalBenchEngine> load({
    required String modelPath,
    String? libraryPath,
    int contextSize = 2048,
    int gpuLayers = 0,
  }) async {
    final resolvedLibraryPath = libraryPath ?? _defaultLibraryPath();
    final engine = await LlamaEngine.spawn(
      libraryPath: resolvedLibraryPath,
      modelParams: ModelParams(path: modelPath, gpuLayers: gpuLayers),
      contextParams: ContextParams(nCtx: contextSize),
    );
    final chat = await engine.createChat();
    return NexLocalBenchEngine._(engine, chat);
  }

  static String _defaultLibraryPath() {
    if (Platform.isAndroid) return 'libllama.so';
    throw UnsupportedError(
      'Phase 0 targets Android only — pass libraryPath explicitly for '
      'desktop/dev testing.',
    );
  }

  /// Sends [prompt] as the next user turn and reports timing and token
  /// counts alongside the text — the entire point of this harness is the
  /// numbers, not the reply.
  Future<BenchResult> ask(String prompt, {int maxTokens = 256}) async {
    _chat.addUser(prompt);

    final buffer = StringBuffer();
    final stopwatch = Stopwatch()..start();
    Duration? firstTokenAt;
    var generatedCount = 0;
    String stopReason = 'unknown';

    await for (final event in _chat.generate(maxTokens: maxTokens)) {
      switch (event) {
        case TokenEvent():
          firstTokenAt ??= stopwatch.elapsed;
          buffer.write(event.text);
        case ShiftEvent():
          break;
        case DoneEvent():
          generatedCount = event.generatedCount;
          stopReason = event.reason.toString();
      }
    }
    stopwatch.stop();

    final generationSpan = firstTokenAt == null
        ? Duration.zero
        : stopwatch.elapsed - firstTokenAt;
    final tokensPerSecond = generationSpan.inMilliseconds == 0
        ? 0.0
        : generatedCount / (generationSpan.inMilliseconds / 1000);

    return BenchResult(
      text: buffer.toString(),
      tokenCount: generatedCount,
      timeToFirstToken: firstTokenAt ?? stopwatch.elapsed,
      totalTime: stopwatch.elapsed,
      tokensPerSecond: tokensPerSecond,
      stopReason: stopReason,
      peakRssMb: ProcessInfo.maxRss / (1024 * 1024),
    );
  }

  Future<void> dispose() => _engine.dispose();
}

/// What Phase 0 actually needs to know about one generation: not the
/// content, the shape of the performance.
class BenchResult {
  const BenchResult({
    required this.text,
    required this.tokenCount,
    required this.timeToFirstToken,
    required this.totalTime,
    required this.tokensPerSecond,
    required this.stopReason,
    required this.peakRssMb,
  });

  final String text;
  final int tokenCount;
  final Duration timeToFirstToken;
  final Duration totalTime;
  final double tokensPerSecond;
  final String stopReason;
  final double peakRssMb;

  @override
  String toString() =>
      'tokens=$tokenCount '
      'ttft=${timeToFirstToken.inMilliseconds}ms '
      'total=${totalTime.inMilliseconds}ms '
      'tok/s=${tokensPerSecond.toStringAsFixed(1)} '
      'peakRss=${peakRssMb.toStringAsFixed(0)}MB '
      'stop=$stopReason';
}
