part of 'ai_provider.dart';

/// What a provider may do besides writing text — each a separate question,
/// since one key can reach a model that reads pictures and an account with
/// no speech service, or the reverse.
enum AiCapability { images, audio, embeddings, video }

/// What asking about one capability found.
enum AiProbeVerdict {
  /// It was asked for and answered the way the feature needs.
  works,

  /// It was asked for and refused, or answered in a way the feature cannot
  /// use — a model that replied without seeing the picture, an endpoint that
  /// answered without a transcript.
  refused,

  /// There is nothing to ask: Nex reaches no such service at this provider.
  /// No request was made.
  absent,

  /// No answer either way: a rate limit, a server error, no network, too
  /// slow. What was known before stays as it was.
  unknown,
}

/// One capability's outcome, with what the provider said when it said no.
@immutable
class AiProbeResult {
  const AiProbeResult(this.verdict, {this.status, this.detail});

  final AiProbeVerdict verdict;

  /// The HTTP status the provider answered with, when there was one.
  final int? status;

  /// The provider's own message, when it gave one.
  final String? detail;

  bool get works => verdict == AiProbeVerdict.works;
}

/// Everything one check found, and when.
@immutable
class AiCapabilityCheck {
  const AiCapabilityCheck({required this.results, required this.at});

  final Map<AiCapability, AiProbeResult> results;
  final DateTime at;

  /// [config] with what was found written into it.
  ///
  /// An [AiProbeVerdict.unknown] keeps whatever the configuration already
  /// held — a rate limit during a re-check must not take away a capability
  /// that worked yesterday — unless that was found for other fields, in
  /// which case it says nothing about these and the provider's default
  /// stands in.
  AiProviderConfig applyTo(AiProviderConfig config) {
    final fingerprint = config.capabilityFingerprint;
    final keep = config.checkedFor.isEmpty || config.checkedFor == fingerprint;
    AiCapabilityMode mode(AiCapability capability, AiCapabilityMode before) =>
        switch (results[capability]?.verdict) {
          AiProbeVerdict.works => AiCapabilityMode.enabled,
          AiProbeVerdict.refused ||
          AiProbeVerdict.absent => AiCapabilityMode.disabled,
          AiProbeVerdict.unknown ||
          null => keep ? before : AiCapabilityMode.automatic,
        };
    return config.copyWith(
      images: mode(AiCapability.images, config.images),
      audio: mode(AiCapability.audio, config.audio),
      embeddings: mode(AiCapability.embeddings, config.embeddings),
      video: mode(AiCapability.video, config.video),
      checkedAt: at.toUtc().toIso8601String(),
      checkedFor: fingerprint,
    );
  }
}

/// The capabilities [after] offers that [before] did not, when both are the
/// same provider and [before] was already in use.
///
/// What a save would start doing on its own. Of the four only search acts
/// unasked — it indexes notes already written — so the client turns its
/// switch off for these and lets the person turn it back on, the same rule
/// an upgrade has kept since OpenRouter's search became possible.
Set<AiCapability> nexNewlyOffered(
  AiProviderConfig before,
  AiProviderConfig after,
) {
  if (!before.isUsable || before.provider != after.provider) return const {};
  return {
    if (!before.supportsImages && after.supportsImages) AiCapability.images,
    if (!before.supportsTranscription && after.supportsTranscription)
      AiCapability.audio,
    if (!before.supportsEmbeddings && after.supportsEmbeddings)
      AiCapability.embeddings,
    if (!before.supportsVideo && after.supportsVideo) AiCapability.video,
  };
}

/// Finds out what [config]'s model can do by asking it (2.1.8).
///
/// Run after the connection test passes, and only then: never in the
/// background, never on a schedule. Each capability is one small request
/// with nothing of the person's in it — a picture of a number made here, a
/// second of tone made here, one fixed sentence, and the first video ever
/// put on YouTube — and each is recorded as a connection test.
///
/// The four go out together, each through an adapter of its own: an
/// adapter remembers one last failure, and four requests sharing it would
/// read each other's. [onResult] hears each one as it lands.
///
/// A model's own word is not taken for any of it. Lists of what a model
/// supports go stale, routers and gateways serve whatever they are pointed
/// at, and the only reliable answer to "can this read a photo" is a photo
/// it has read.
Future<AiCapabilityCheck> nexCheckCapabilities(
  AiProviderConfig config, {
  http.Client? client,
  void Function(AiCapability capability, AiProbeResult result)? onResult,
  DateTime Function()? clock,
  @visibleForTesting Duration? limit,
}) async {
  final results = <AiCapability, AiProbeResult>{};
  Future<void> run(
    AiCapability capability,
    Duration budget,
    Future<AiProbeResult> Function(CloudAIAdapter adapter) probe,
  ) async {
    final adapter = CloudAIAdapter(
      config: config,
      client: client,
      mediaTimeout: limit ?? budget,
    );
    AiProbeResult result;
    try {
      result = await NexDisclosureLog.about(
        () => probe(adapter),
        purpose: DisclosurePurpose.connectionTest,
        media: _checkMedia[capability],
      ).timeout(limit ?? budget);
    } on TimeoutException {
      result = const AiProbeResult(AiProbeVerdict.unknown);
    } on AiUnavailableException catch (error) {
      result = adapter._probeFailure(fallback: error.message);
    } on FormatException {
      // A 200 whose body is not the JSON the feature reads.
      result = const AiProbeResult(AiProbeVerdict.refused);
    } catch (_) {
      // No network, a reset connection, a refused TLS handshake.
      result = const AiProbeResult(AiProbeVerdict.unknown);
    } finally {
      adapter.close();
    }
    results[capability] = result;
    onResult?.call(capability, result);
  }

  if (!config.isUsable) {
    return AiCapabilityCheck(results: const {}, at: (clock ?? DateTime.now)());
  }
  await Future.wait([
    run(AiCapability.images, const Duration(seconds: 60), _probeImages),
    run(AiCapability.audio, const Duration(seconds: 60), _probeAudio),
    run(AiCapability.embeddings, const Duration(seconds: 30), _probeEmbeddings),
    run(AiCapability.video, const Duration(seconds: 90), _probeVideo),
  ]);
  return AiCapabilityCheck(results: results, at: (clock ?? DateTime.now)());
}

/// What the request log names each test file, so nobody reading it wonders
/// which of their photos went.
const _checkMedia = {
  AiCapability.images: 'nex-check.png',
  AiCapability.audio: 'nex-check.wav',
};

/// The number drawn in the test picture. Two digits: one a model could
/// guess, two it cannot.
const _checkNumber = '47';

Future<AiProbeResult> _probeImages(CloudAIAdapter adapter) async {
  final reply = await adapter._complete(
    'You are being checked for whether you can see pictures. Reply with '
        'only the number written in the picture, in Western digits, and nothing '
        'else. If there is no picture, reply exactly: none',
    'What number is written in this picture?',
    // No ceiling where the provider allows that: a model that thinks first
    // spends a small budget before it writes a word, and its silence would
    // read as blindness. Anthropic requires one, and its stand-in for none
    // is more than older Claude models accept — a 400 that is not about
    // pictures at all.
    maxTokens: adapter.config.provider.format == AiWireFormat.anthropic
        ? 1024
        : null,
    media: nexCheckPicture(),
    mediaMimeType: 'image/png',
  );
  if (reply == null) return adapter._probeFailure();
  // A model can see and still answer in its own digits.
  final seen = nexLatinDigits(
    reply,
  ).contains(RegExp('(?<![0-9])$_checkNumber(?![0-9])'));
  return seen
      ? const AiProbeResult(AiProbeVerdict.works)
      : AiProbeResult(AiProbeVerdict.refused, detail: _clip(reply));
}

Future<AiProbeResult> _probeAudio(CloudAIAdapter adapter) async {
  final config = adapter.config;
  if (config.provider.format == AiWireFormat.gemini) {
    // Not through `_transcribe`: a tone has no words to transcribe, and an
    // empty transcript is what that path calls a failure. What matters here
    // is whether the speech model takes a recording at all.
    final reply = await adapter._complete(
      'Say in a few words what you hear in the recording.',
      'What does this recording sound like?',
      maxTokens: null,
      media: nexCheckTone(),
      mediaMimeType: 'audio/wav',
      modelOverride: config.resolvedTranscriptionModel,
    );
    // An answer with no words in it is still the recording accepted.
    return reply != null || adapter._lastFailure == null
        ? const AiProbeResult(AiProbeVerdict.works)
        : adapter._probeFailure();
  }
  if (config.transcriptionEndpoint == null) {
    return const AiProbeResult(AiProbeVerdict.absent);
  }
  await adapter._transcribe(nexCheckTone(), _checkMedia[AiCapability.audio]!);
  return const AiProbeResult(AiProbeVerdict.works);
}

Future<AiProbeResult> _probeEmbeddings(CloudAIAdapter adapter) async {
  if (adapter.config.embeddingEndpoint == null) {
    return const AiProbeResult(AiProbeVerdict.absent);
  }
  final vector = await adapter._embed(
    'Nex checks that search can index this sentence.',
  );
  return vector.dimensions > 0
      ? const AiProbeResult(AiProbeVerdict.works)
      : const AiProbeResult(AiProbeVerdict.refused);
}

/// "Me at the zoo": nineteen seconds, public since 2005, and the video
/// YouTube is least likely ever to take down.
const nexCheckVideo = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

Future<AiProbeResult> _probeVideo(CloudAIAdapter adapter) async {
  if (adapter.config.provider != AiProvider.gemini) {
    return const AiProbeResult(AiProbeVerdict.absent);
  }
  // The same request "Analyze video" makes, so what passes here is what
  // works there.
  final reply = await adapter._watchVideo(
    'Reply with one word: the animals standing behind the man in the video.',
    'The video is attached.',
    url: nexCheckVideo,
  );
  if (reply == null) return adapter._probeFailure();
  // An answer is not proof of watching. A gateway can drop the video and
  // pass the words on, and the model then answers about nothing — but the
  // link is not in the words, so it cannot know there were elephants.
  return RegExp('elephant|فیل', caseSensitive: false).hasMatch(reply)
      ? const AiProbeResult(AiProbeVerdict.works)
      : AiProbeResult(AiProbeVerdict.refused, detail: _clip(reply));
}

String _clip(String text) {
  final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return line.length > 120 ? '${line.substring(0, 120)}…' : line;
}

extension on CloudAIAdapter {
  /// What the last request's failure means for a capability.
  ///
  /// A refusal is a status the same request would get again tomorrow — the
  /// model takes no pictures, the account has no speech service, the
  /// endpoint is not there. Everything else (a rate limit, an empty
  /// wallet, a server having a bad minute, a reply with no text at all)
  /// could go either way, and is reported as not known.
  AiProbeResult _probeFailure({String? fallback}) {
    final failure = _lastFailure;
    if (failure == null) {
      // An exception with no status behind it: a 200 whose body held no
      // transcript or vector. The feature reads that body and would fail
      // on it the same way. With no exception, the reply had no text.
      return fallback == null
          ? const AiProbeResult(AiProbeVerdict.unknown)
          : AiProbeResult(AiProbeVerdict.refused, detail: fallback);
    }
    const refusals = {400, 401, 403, 404, 405, 406, 410, 413, 415, 422};
    return AiProbeResult(
      refusals.contains(failure.status)
          ? AiProbeVerdict.refused
          : AiProbeVerdict.unknown,
      status: failure.status == 0 ? null : failure.status,
      detail: failure.message,
    );
  }
}

/// Persian and Arabic-Indic digits as Latin ones; nothing else changes.
@visibleForTesting
String nexLatinDigits(String text) =>
    text.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (match) {
      final unit = match[0]!.codeUnitAt(0);
      return String.fromCharCode(
        0x30 + unit - (unit >= 0x06F0 ? 0x06F0 : 0x0660),
      );
    });

/// The picture the image check sends: [_checkNumber] in large blocky
/// digits, black on white, as a grayscale PNG built here.
///
/// Drawn rather than shipped so there is nothing to keep in step with the
/// number, and so a reader can see what it shows: the glyphs below are the
/// whole of it.
@visibleForTesting
Uint8List nexCheckPicture() {
  const glyphs = {
    '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  };
  const scale = 12, margin = 36, gap = 24;
  final digits = [for (final c in _checkNumber.split('')) glyphs[c]!];
  final width = margin * 2 + digits.length * 5 * scale + gap;
  final height = margin * 2 + 7 * scale;
  // One filter byte (0, none) before each row of 8-bit gray pixels.
  final raw = Uint8List((width + 1) * height);
  for (var y = 0; y < height; y++) {
    final row = y * (width + 1);
    raw[row] = 0;
    for (var x = 0; x < width; x++) {
      var ink = false;
      final gy = (y - margin) ~/ scale;
      if (y >= margin && gy < 7) {
        for (var d = 0; d < digits.length; d++) {
          final left = margin + d * (5 * scale + gap);
          final gx = (x - left) ~/ scale;
          if (x >= left && gx < 5 && digits[d][gy][gx] == '1') ink = true;
        }
      }
      raw[row + 1 + x] = ink ? 0 : 255;
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    return Uint8List.fromList([
      ..._uint32(data.length),
      ...body,
      ..._uint32(_crc32(body)),
    ]);
  }

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    ...chunk('IHDR', [
      ..._uint32(width),
      ..._uint32(height),
      8, // bit depth
      0, // grayscale
      0, 0, 0, // deflate, adaptive filtering, no interlace
    ]),
    ...chunk('IDAT', ZLibCodec(level: 9).encode(raw)),
    ...chunk('IEND', const []),
  ]);
}

/// One second of a soft 440 Hz tone as 16 kHz mono 16-bit WAV — something
/// to hear, with nothing of anyone's in it.
@visibleForTesting
Uint8List nexCheckTone() {
  const rate = 16000, samples = rate;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little); // bits per sample
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    // Faded in and out over 50 ms so it starts and stops without a click.
    final fade = math.min(1.0, math.min(i, samples - i) / (rate * 0.05));
    final value = math.sin(2 * math.pi * 440 * i / rate) * 0.2 * fade;
    data.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
