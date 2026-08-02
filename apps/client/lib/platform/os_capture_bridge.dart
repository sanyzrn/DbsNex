import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'nex_services.dart';

/// Bridges Android widget + share-intent into the same capture path as in-app
/// Quick Capture (FR-8 / ADR-027) — zero mandatory fields, auto-save.
class OsCaptureBridge {
  OsCaptureBridge(this.services);

  final NexServices services;
  static const _channel = MethodChannel('nex/os_capture');
  final _events = StreamController<Map<Object?, Object?>>.broadcast();

  Stream<Map<Object?, Object?>> get events => _events.stream;

  /// Whether this platform has the native half of the bridge.
  ///
  /// Only Android registers `nex/os_capture`; the widget, the share target and
  /// the pending-intent queue are all Android concepts. Windows has no
  /// equivalent surface yet.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOsCapture' && call.arguments is Map) {
        final payload = Map<Object?, Object?>.from(call.arguments as Map);
        await handle(payload);
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
      // Belt and braces behind [isSupported]. This call used to be
      // unguarded, and on Windows — where nothing registers the channel — it
      // threw straight out of `start()`, out of `NexServices.bootstrap`, and
      // into the host's FutureBuilder. The app did not open a timeline at all
      // on a shipped desktop target; it opened an error screen. Nothing in CI
      // caught it, because the Windows job builds the app and never runs it.
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
        final path = payload['path'] as String?;
        if (path == null) return;
        final file = File(path);
        if (!file.existsSync()) return;
        final bytes = await file.readAsBytes();
        final dest = await _copyIntoMedia(
          file,
          bytes,
          preferredName: payload['filename'] as String?,
        );
        await services.capturePhoto(
          mediaUri: dest,
          mediaBytes: Uint8List.fromList(bytes),
        );
        await services.refreshTimeline();
      case 'shared_file':
        final path = payload['path'] as String?;
        if (path == null) return;
        final file = File(path);
        if (!file.existsSync()) return;
        final bytes = await file.readAsBytes();
        final originalName = _resolveOriginalFilename(
          payload['filename'] as String?,
          path,
        );
        final dest = await _copyIntoMedia(
          file,
          bytes,
          preferredName: originalName,
        );
        await services.captureFile(
          mediaUri: dest,
          mediaBytes: Uint8List.fromList(bytes),
          originalFilename: originalName,
          mimeType: payload['mimeType'] as String?,
        );
        await services.refreshTimeline();
    }
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

  Future<String> _copyIntoMedia(
    File source,
    List<int> bytes, {
    String? preferredName,
  }) async {
    final base = preferredName?.trim().isNotEmpty == true
        ? p.basename(preferredName!.trim())
        : _humanizeBasename(p.basename(source.path));
    final name = 'media-${DateTime.now().millisecondsSinceEpoch}-$base';
    final dest = File('${services.mediaDir}/$name');
    await dest.writeAsBytes(bytes, flush: true);
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
