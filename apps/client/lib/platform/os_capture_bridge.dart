import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
// `hide Summary`: nex_core exports one too, and nex_services already
// carries the same guard for the same reason.
import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

import 'nex_services.dart';

/// What was refused, and how big it was.
///
/// Carries the numbers rather than a finished sentence: the message is
/// localised, and the file's own size is what makes the refusal make sense
/// instead of sounding arbitrary.
class RejectedShare {
  const RejectedShare({
    required this.filename,
    required this.bytes,
    required this.limit,
  });

  final String filename;
  final int bytes;

  /// The limit in force, carried along so the message can name it without
  /// reaching back to the bridge for a number it already knew.
  final int limit;
}

/// Bridges Android widget + share-intent into the same capture path as in-app
/// Quick Capture (FR-8 / ADR-027) — zero mandatory fields, auto-save.
class OsCaptureBridge {
  OsCaptureBridge(
    this.services, {
    this.maxAttachmentBytes = defaultMaxAttachmentBytes,
  });

  final NexServices services;
  static const _channel = MethodChannel('nex/os_capture');
  final _events = StreamController<Map<Object?, Object?>>.broadcast();

  /// The largest attachment Nex will take in.
  ///
  /// Nex is a notes app. The cost of an attachment is not what it weighs
  /// once: the automatic backup zips the whole media directory and keeps
  /// [NexDatabase.backupRetention] of them, so one file is stored its own
  /// size plus up to five times over again, and every backup after it is
  /// slower and larger for good. A two-gigabyte video shared in came to
  /// roughly fourteen gigabytes by that arithmetic — and reported itself as
  /// an out-of-memory crash on the next launch rather than as a full disk.
  ///
  /// A hundred megabytes clears everything this app is for — a phone photo is
  /// under twelve, a long voice note about fifty, a document rarely twenty —
  /// while keeping the worst case a file can impose to about half a gigabyte.
  static const defaultMaxAttachmentBytes = 100 * 1024 * 1024;

  /// The limit in force. Production never passes it.
  ///
  /// A parameter rather than only a constant so a test can reach the rule
  /// without writing a hundred-megabyte file to prove it — the same trade as
  /// `SyncClient.requestTimeout`, and for the same reason: a case that costs
  /// that much to run is a case people stop running.
  final int maxAttachmentBytes;

  /// Called when something was shared in that Nex will not keep.
  ///
  /// A callback plus [takeRejection] rather than one or the other, because a
  /// share arrives in two different worlds: into a running app, where a
  /// screen is listening, and as the intent that launched it, where the
  /// refusal happens during bootstrap and there is nothing on screen yet.
  /// The reminder launch path already has this exact shape for the same
  /// reason — `onOpenNote` beside `takeLaunchNoteId`.
  void Function(RejectedShare rejection)? onRejected;

  RejectedShare? _rejection;

  /// The refusal that happened before anything was listening, once.
  RejectedShare? takeRejection() {
    final value = _rejection;
    _rejection = null;
    return value;
  }

  void _reject(RejectedShare rejection) {
    _rejection = rejection;
    onRejected?.call(rejection);
  }

  Stream<Map<Object?, Object?>> get events => _events.stream;

  /// Whether this platform has the native half of the bridge.
  ///
  /// Only Android registers `nex/os_capture`; the widget, the share target and
  /// the pending-intent queue are all Android concepts. Windows has no
  /// equivalent surface yet.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Registers the handler and drains anything the native side queued while
  /// Dart was not listening.
  ///
  /// No `isSupported` check any more. The channel is the authority on whether
  /// it exists — the `MissingPluginException` catch below already says so —
  /// and a `Platform.isAndroid` check up here made this method unreachable
  /// from any test, since a widget test runs on the host. That is the same
  /// trade [NexVideoPreview.poster] states in its own doc comment, and the
  /// reason the reminder scheduling path had to be pulled apart before it
  /// could be covered at all.
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOsCapture' && call.arguments is Map) {
        final payload = Map<Object?, Object?>.from(call.arguments as Map);
        await handle(payload);
        // Acknowledge it, or the same capture arrives twice.
        //
        // `enqueue` on the native side sets `pending` for *every* payload and
        // clears it nowhere — `takePending` is the only thing that does. A
        // live push therefore handled the capture and left a copy behind, and
        // the next `start()` in the same process picked that copy up and
        // captured it again. Restoring a backup is exactly that: it calls
        // `NexRestartScope.restart()`, which builds a new bridge and starts
        // it, same process and same Activity — so sharing a photo in and then
        // restoring left two of it.
        //
        // After [handle], not before: a process killed mid-handle then still
        // has the payload queued and captures it once on the next launch,
        // where consuming first would have lost it outright.
        await _consumePending();
        _events.add(payload);
      }
    });
    try {
      final pending = await _channel.invokeMethod<dynamic>('takePending');
      if (pending is Map) {
        final payload = Map<Object?, Object?>.from(pending);
        await handle(payload);
        _events.add(payload);
      }
    } on MissingPluginException {
      // The whole platform guard now, rather than belt and braces behind
      // one. This call used to be
      // unguarded, and on Windows — where nothing registers the channel — it
      // threw straight out of `start()`, out of `NexServices.bootstrap`, and
      // into the host's FutureBuilder. The app did not open a timeline at all
      // on a shipped desktop target; it opened an error screen. Nothing in CI
      // caught it, because the Windows job builds the app and never runs it.
    }
  }

  /// Clears the native side's copy of the payload just handled.
  ///
  /// Its return value is deliberately dropped: what came back is the same
  /// thing that was just captured, and on a platform with no native half
  /// there is nothing to clear.
  Future<void> _consumePending() async {
    try {
      await _channel.invokeMethod<dynamic>('takePending');
    } on MissingPluginException {
      // No native side — nothing was queued in the first place.
    }
  }

  Future<void> handle(Map<Object?, Object?> payload) async {
    final type = payload['type'] as String?;
    switch (type) {
      case 'text_capture':
        // Widget opens into text capture — signal UI; no note until content.
        return;
      case 'shared_text':
        final text = (payload['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        await services.captureText(text);
        await services.refreshTimeline();
      case 'shared_photo':
        final file = await _fetch(payload);
        if (file == null) return;
        final name = payload['filename'] as String?;
        final dest = await _copyIntoMedia(file, preferredName: name);
        await services.capturePhoto(
          mediaUri: dest,
          mediaHash: await _hashOf(dest),
        );
        await _discardIncoming(file);
        await services.refreshTimeline();
      case 'shared_file':
        final file = await _fetch(payload);
        if (file == null) return;
        final originalName = _resolveOriginalFilename(
          payload['filename'] as String?,
          file.path,
        );
        final dest = await _copyIntoMedia(file, preferredName: originalName);
        await services.captureFile(
          mediaUri: dest,
          mediaHash: await _hashOf(dest),
          originalFilename: originalName,
          mimeType: payload['mimeType'] as String?,
        );
        await _discardIncoming(file);
        await services.refreshTimeline();
    }
  }

  /// The file a share refers to, in hand and inside the limit — or null,
  /// meaning it was refused, or there was nothing to fetch.
  ///
  /// A payload arrives in one of two shapes, and both are legitimate. A share
  /// intent carries a `uri` and the provider's own account of the file: the
  /// bytes have not moved yet, so a file over the limit is refused here for
  /// the cost of a cursor query. The in-app file picker carries a `path`,
  /// because `ACTION_OPEN_DOCUMENT` has already produced a copy by the time
  /// its result comes back.
  ///
  /// This is the fix for a refusal that took as long as an acceptance. The
  /// native side used to copy every shared file into the cache before Dart
  /// was told the first thing about it, so refusing a two-gigabyte video
  /// meant writing two gigabytes to disk, measuring them, deleting them, and
  /// only then saying the file was too big — with the app apparently frozen
  /// throughout, and on a cold start with the splash screen still up.
  Future<File?> _fetch(Map<Object?, Object?> payload) async {
    final name = payload['filename'] as String?;
    // What the provider says before anything is copied. -1, or absent, means
    // it would not say — then the only way to know is to fetch and measure,
    // which is what happened to every file before this.
    final declared = int.tryParse('${payload['size'] ?? ''}') ?? -1;
    if (declared > maxAttachmentBytes) {
      _reject(
        RejectedShare(
          filename: _refusedName(name, payload['uri'] as String?),
          bytes: declared,
          limit: maxAttachmentBytes,
        ),
      );
      // Nothing was copied, so there is nothing to take back.
      return null;
    }
    final path =
        payload['path'] as String? ??
        await _copyShared(payload['uri'] as String?);
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    // The backstop, for a provider that would not name a size and for the
    // picker's already-copied path. Same rule, later and more expensively.
    if (await _refuseIfTooLarge(file, name)) return null;
    return file;
  }

  /// Asks the native side to copy the shared file out of its provider.
  ///
  /// Null on every failure, including a platform with no native half: the
  /// caller does the same thing about all of them, which is to capture
  /// nothing and leave the library alone.
  Future<String?> _copyShared(String? uri) async {
    if (uri == null) return null;
    try {
      return await _channel.invokeMethod<String>('copyShared', <String, Object>{
        'uri': uri,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// What to call a file in the refusal message when there is no copy of it
  /// on disk to fall back on.
  static String _refusedName(String? provided, String? uri) {
    final name = provided?.trim();
    if (name != null && name.isNotEmpty) return p.basename(name);
    final segments = uri == null
        ? const <String>[]
        : Uri.tryParse(uri)?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    return last.isEmpty ? 'file' : last;
  }

  /// Pick a file: the platform channel on Android, the system dialog elsewhere.
  ///
  /// This was channel-only, so the File capture option threw
  /// MissingPluginException on Windows — the one capture type that had no
  /// working path there. `file_selector` is already a dependency and has an
  /// endorsed Windows implementation; the media picker has been using it for
  /// images all along.
  static Future<PickedOsFile?> pickFile() async {
    if (!isSupported) {
      final file = await openFile();
      if (file == null) return null;
      return PickedOsFile(
        path: file.path,
        filename: file.name,
        mimeType: file.mimeType,
      );
    }
    final result = await _channel.invokeMethod<dynamic>('pickFile');
    if (result == null) return null;
    if (result is String) {
      // Legacy string path — basename may be a cache placeholder.
      return PickedOsFile(
        path: result,
        filename: _humanizeBasename(p.basename(result)),
        mimeType: null,
      );
    }
    if (result is Map) {
      final path = result['path'] as String?;
      if (path == null) return null;
      return PickedOsFile(
        path: path,
        filename: _resolveOriginalFilename(result['filename'] as String?, path),
        mimeType: result['mimeType'] as String?,
      );
    }
    return null;
  }

  /// Whether [file] is too heavy to keep, refusing it if so.
  ///
  /// Checked here rather than on the Android side, where the size is also
  /// available. This is the one place both ways in meet — a share intent and
  /// the in-app file picker both arrive at [handle] — so it is the one place
  /// the rule can be stated once, and the only one a test on a host can
  /// reach.
  ///
  /// The expensive half of the rule, and no longer the usual one. It applies
  /// to a file already on disk: the picker's copy, or a share whose provider
  /// would not name a size. When the size is known, [_fetch] refuses before
  /// anything is copied and this is never reached. [_discardIncoming] takes
  /// back the copy in the cases where one was made.
  Future<bool> _refuseIfTooLarge(File file, String? name) async {
    final bytes = await file.length();
    if (bytes <= maxAttachmentBytes) return false;
    _reject(
      RejectedShare(
        filename: name?.trim().isNotEmpty == true
            ? p.basename(name!.trim())
            : p.basename(file.path),
        bytes: bytes,
        limit: maxAttachmentBytes,
      ),
    );
    await _discardIncoming(file);
    return true;
  }

  /// Removes the copy the native side left in the cache.
  ///
  /// `copyUri` writes every shared file into `cacheDir/shared` before Dart
  /// ever sees it, and nothing deleted it afterwards — so each share cost
  /// twice what it kept, and the second copy stayed until Android decided to
  /// reclaim the cache. Called once the file is safely in the media
  /// directory, and also when it was refused, which is the case where keeping
  /// it would be pure waste.
  ///
  /// Deliberately silent about failure. This is the copy, never the original:
  /// the app is handed a content URI it cannot write through, so what it
  /// deletes here is always something it made itself. Nothing the person
  /// shared is at risk, and a cache file that will not delete is Android's to
  /// sweep, not a reason to fail a capture that already succeeded.
  Future<void> _discardIncoming(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Left for the OS.
    }
  }

  /// The content hash of the file just written, or a failure.
  ///
  /// Not `?? ''`. The hash is what tells two copies of the same attachment
  /// apart from two different ones, so an empty string is not a missing
  /// value — it is a value that every un-hashable attachment would share,
  /// which is the one answer that makes them look identical to each other.
  /// The file was created a moment ago by [_copyIntoMedia]; if it cannot be
  /// read now, the capture should fail loudly rather than store a note whose
  /// identity is a lie.
  Future<String> _hashOf(String path) async {
    final hash = await sha256OfFile(path);
    if (hash == null) {
      throw StateError('media copied to $path could not be read back');
    }
    return hash;
  }

  /// Puts the shared file where the library keeps its media, and answers where.
  ///
  /// `source.copy` rather than reading the bytes and writing them back. What
  /// arrives here is whatever somebody shared into the app, and a two-gigabyte
  /// video is an ordinary thing to share: the old shape read the whole file
  /// into the heap, handed the same list to `writeAsBytes`, and then made a
  /// second full copy of it for the hash. Four gigabytes of peak for a
  /// two-gigabyte file, on a phone — reported as an out-of-memory error on
  /// the launch that tried to finish the share. `copy` streams it and holds
  /// none of it.
  Future<String> _copyIntoMedia(File source, {String? preferredName}) async {
    final base = preferredName?.trim().isNotEmpty == true
        ? p.basename(preferredName!.trim())
        : _humanizeBasename(p.basename(source.path));
    final name = 'media-${DateTime.now().millisecondsSinceEpoch}-$base';
    final dest = File('${services.mediaDir}/$name');
    await source.copy(dest.path);
    return dest.path;
  }

  static String _resolveOriginalFilename(String? provided, String path) {
    if (provided != null && provided.trim().isNotEmpty) {
      return p.basename(provided.trim());
    }
    return _humanizeBasename(p.basename(path));
  }

  /// Strip leading `timestamp-` prefixes from cache copies when no better name.
  static String _humanizeBasename(String name) {
    final stripped = name.replaceFirst(RegExp(r'^\d{10,}-'), '');
    if (stripped.isNotEmpty && !stripped.endsWith('.bin')) return stripped;
    return name;
  }

  void dispose() {
    _events.close();
  }
}

class PickedOsFile {
  const PickedOsFile({
    required this.path,
    required this.filename,
    this.mimeType,
  });

  final String path;
  final String filename;
  final String? mimeType;
}
