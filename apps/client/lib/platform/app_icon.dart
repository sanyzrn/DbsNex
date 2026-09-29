import 'dart:io';

import 'package:flutter/services.dart';

/// The launcher icon, chosen from six in Settings → Appearance → Theme.
///
/// Android only: the icon is switched by enabling one of six manifest aliases
/// (see `NexAppIcon.kt`). Everywhere else the choice is simply not offered.
abstract final class NexAppIcons {
  /// In display order. `default` is the app's own icon; the others are built
  /// from `apps/client/app_icons/` by `tools/generate_app_icons.py`.
  static const ids = ['default', 'alt1', 'alt2', 'alt3', 'alt4', 'alt5'];

  static const _channel = MethodChannel('nex/os_capture');

  static bool get supported => Platform.isAndroid;

  /// The preview shown for [id] in Settings.
  static String preview(String id) => 'assets/app_icons/$id.png';

  static Future<String> current() async {
    if (!supported) return 'default';
    try {
      final id = await _channel.invokeMethod<String>('appIcon');
      return ids.contains(id) ? id! : 'default';
    } on PlatformException {
      return 'default';
    } on MissingPluginException {
      return 'default';
    }
  }

  /// False when the switch could not be made.
  static Future<bool> set(String id) async {
    if (!supported || !ids.contains(id)) return false;
    try {
      await _channel.invokeMethod<void>('setAppIcon', {'id': id});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
