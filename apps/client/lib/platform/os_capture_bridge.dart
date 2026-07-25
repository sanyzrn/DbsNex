import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
        final dest = await _copyIntoMedia(file, bytes);
        services.capture.submitPhotoCapture(
          mediaUri: dest,
          mediaBytes: Uint8List.fromList(bytes),
        );
        services.refreshTimeline();
    }
  }

  Future<String> _copyIntoMedia(File source, List<int> bytes) async {
    final name =
        'shared-${DateTime.now().millisecondsSinceEpoch}${_ext(source.path)}';
    final dest = File('${services.mediaDir}/$name');
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  String _ext(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '.jpg';
    return path.substring(i);
  }

  void dispose() {
    _events.close();
  }
}
