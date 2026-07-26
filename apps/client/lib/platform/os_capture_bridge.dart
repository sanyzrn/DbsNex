import 'dart:async';
import 'dart:io';

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

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOsCapture' && call.arguments is Map) {
        final payload = Map<Object?, Object?>.from(call.arguments as Map);
        await handle(payload);
        _events.add(payload);
      }
    });
    final pending = await _channel.invokeMethod<dynamic>('takePending');
    if (pending is Map) {
      final payload = Map<Object?, Object?>.from(pending);
      await handle(payload);
      _events.add(payload);
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
        services.capture.submitTextCapture(text);
        services.refreshTimeline();
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
        services.capture.submitPhotoCapture(
          mediaUri: dest,
          mediaBytes: Uint8List.fromList(bytes),
        );
        services.refreshTimeline();
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
        services.capture.submitFileCapture(
          mediaUri: dest,
          mediaBytes: Uint8List.fromList(bytes),
          originalFilename: originalName,
          mimeType: payload['mimeType'] as String?,
        );
        services.refreshTimeline();
    }
  }

  /// Pick a file via the platform channel; returns path + original name + MIME.
  static Future<PickedOsFile?> pickFile() async {
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
        filename: _resolveOriginalFilename(
          result['filename'] as String?,
          path,
        ),
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
