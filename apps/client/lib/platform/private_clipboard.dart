import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android marks the clip sensitive to suppress its system preview. Expiration
/// is best effort: OS clipboard restrictions or process death may delay it.
abstract final class PrivateClipboard {
  static Timer? _clear;

  /// What was last copied by this class, so a wipe only ever clears a copy
  /// that is still ours — never something the person copied since.
  static String? _ours;

  static Future<void> copy(String value) async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('nex/os_capture')
            .invokeMethod<void>('copyPrivate', {'text': value});
        return;
      } on PlatformException {
        // The native half refused (PERF-06): copied the ordinary way below,
        // with the same half-minute wipe, rather than a tap that did nothing.
      } on MissingPluginException {
        // An engine without the native half: the same.
      }
    }
    await Clipboard.setData(ClipboardData(text: value));
    _ours = value;
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 30), _wipe);
  }

  /// Clears the copy now, if ours is still what the clipboard holds. The
  /// timer would have done this at its leisure; the vault hiding or locking
  /// is the moment a copied secret has outlived its purpose, and waiting
  /// out the timer leaves it readable to whatever is on screen next
  /// (SEC-05). Nothing is done when there is no outstanding copy — a
  /// user's or another app's clip is never touched.
  static Future<void> sweepNow() async {
    final timer = _clear;
    if (timer == null) return;
    timer.cancel();
    await _wipe();
  }

  static Future<void> _wipe() async {
    _clear = null;
    final value = _ours;
    _ours = null;
    if (value == null) return;
    try {
      if ((await Clipboard.getData(Clipboard.kTextPlain))?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      /* Clipboard ownership may have moved to another app. */
    }
  }
}
