import 'package:flutter/services.dart';

/// Keeps the display lit while something is meant to be watched without a
/// touch — a breathing session, where the screen timing out half a minute in
/// would end the guide mid-breath (2.4.0).
///
/// Window-scoped on Android (`FLAG_KEEP_SCREEN_ON`), so it lasts only while
/// Nex is on screen and costs no permission. Elsewhere it does nothing.
abstract final class NexKeepScreenOn {
  static const _channel = MethodChannel('nex/os_capture');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on MissingPluginException {
      // No native half: nothing to keep on.
    } on PlatformException {
      // A window that is going away; nothing to keep on either.
    }
  }
}
