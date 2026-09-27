import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Android marks the clip sensitive to suppress its system preview. Expiration
/// is best effort: OS clipboard restrictions or process death may delay it.
abstract final class PrivateClipboard {
  static Timer? _clear;
  static Future<void> copy(String value) async {
    if (Platform.isAndroid) {
      await const MethodChannel(
        'nex/os_capture',
      ).invokeMethod<void>('copyPrivate', {'text': value});
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 30), () async {
      try {
        if ((await Clipboard.getData(Clipboard.kTextPlain))?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        /* Clipboard ownership may have moved to another app. */
      }
    });
  }
}
