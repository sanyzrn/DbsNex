import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_store.dart';

/// Why a device cannot run a local model, in terms someone can act on.
enum LocalAiBlocker {
  /// Not Android or iOS — the inference plugin registers nowhere else.
  platform,

  /// A 32-bit or x86 Android build. LiteRT-LM ships arm64 only.
  architecture,

  /// The weights would not fit, or would leave the phone with nothing.
  storage,

  /// Nex has not published this model yet — see [NexModels].
  notPublished,
}

/// What a device can be told about local AI before anything is downloaded.
class LocalAiSupport {
  const LocalAiSupport({required this.blocker, required this.freeBytes});

  /// Null when the device can run it.
  final LocalAiBlocker? blocker;

  /// Free space seen at the time of the check, or null when it could not be
  /// read. Shown alongside the model's size so "not enough room" is a number
  /// and not a verdict.
  final int? freeBytes;

  bool get supported => blocker == null;
}

/// Decides whether local AI is offered on this device at all.
///
/// The rule this follows is the one `aiCapabilities` already established: a
/// capability the device cannot honour is *absent*, not present-and-failing.
/// Offering a 2.6 GB download that cannot load afterwards is worse than never
/// mentioning it, particularly when the download is the expensive part and the
/// failure only appears at the end of it.
abstract final class LocalAi {
  /// Headroom demanded beyond the model itself.
  ///
  /// The join writes the assembled file while the parts are still on disk, so
  /// the peak is roughly twice the model — and a phone driven to zero free
  /// bytes misbehaves in ways that have nothing to do with this feature. The
  /// check asks for the peak plus a margin rather than for the final size.
  static const _headroomBytes = 512 * 1024 * 1024;

  /// The architectures LiteRT-LM ships native code for.
  static const _supportedAbis = {'arm64-v8a', 'arm64', 'aarch64'};

  static Future<LocalAiSupport> check(
    ModelRelease model, {
    Directory? storageProbe,
    @visibleForTesting Set<String>? abisOverride,
    @visibleForTesting int? freeBytesOverride,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const LocalAiSupport(
        blocker: LocalAiBlocker.platform,
        freeBytes: null,
      );
    }
    if (!NexModelStore.installable(model)) {
      return const LocalAiSupport(
        blocker: LocalAiBlocker.notPublished,
        freeBytes: null,
      );
    }
    final abis = abisOverride ?? _deviceAbis();
    // iOS is 64-bit only and reports nothing here, so an empty set is not a
    // failure — only a set that is present and contains no arm64 is.
    if (abis.isNotEmpty && !abis.any(_supportedAbis.contains)) {
      return const LocalAiSupport(
        blocker: LocalAiBlocker.architecture,
        freeBytes: null,
      );
    }

    final free = freeBytesOverride ?? await _freeBytes(storageProbe);
    // Unknown free space is not treated as "no room". A storage API that
    // declines to answer should not withhold a feature the phone can run; the
    // download will fail loudly and recoverably if it genuinely does not fit.
    if (free != null && free < model.sizeBytes * 2 + _headroomBytes) {
      return LocalAiSupport(blocker: LocalAiBlocker.storage, freeBytes: free);
    }
    return LocalAiSupport(blocker: null, freeBytes: free);
  }

  /// The ABIs this process was built for.
  ///
  /// Read from the running executable rather than from a plugin: `Platform`
  /// already knows, it costs nothing, and it avoids another native dependency
  /// for one string.
  static Set<String> _deviceAbis() {
    if (kIsWeb) return const {};
    final version = Platform.version.toLowerCase();
    return {
      for (final abi in _supportedAbis)
        if (version.contains(abi)) abi,
      // Anything explicitly 32-bit is worth naming so the check above has
      // something to reject rather than an empty set to wave through.
      if (version.contains('arm') && !version.contains('arm64')) 'armeabi-v7a',
      if (version.contains('ia32') || version.contains('x86')) 'x86',
    };
  }

  static Future<int?> _freeBytes(Directory? probe) async {
    final dir = probe ?? Directory.systemTemp;
    try {
      final stat = await Process.run('df', ['-k', dir.path]);
      if (stat.exitCode != 0) return null;
      final lines = '${stat.stdout}'.trim().split('\n');
      if (lines.length < 2) return null;
      final columns = lines.last.trim().split(RegExp(r'\s+'));
      // `df -k` reports 1K blocks; the available column is fourth on both
      // Android's toybox and iOS's BSD userland.
      if (columns.length < 4) return null;
      final kilobytes = int.tryParse(columns[3]);
      return kilobytes == null ? null : kilobytes * 1024;
    } catch (_) {
      // No `df`, no permission, a platform that sandboxes process spawning —
      // all of which mean "unknown", which the caller treats as permissive.
      return null;
    }
  }
}
