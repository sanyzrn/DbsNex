import 'dart:io';

import 'package:flutter/services.dart';

/// Sends someone to the OS screen that owns a notification channel's sound.
///
/// There is no in-app sound picker, and the reason is the platform's, not a
/// shortcut: on Android a channel's sound, vibration and importance are fixed
/// when the channel is created and belong to the user from that moment on.
/// An app cannot change them afterwards — that is the whole point of channels
/// — so a list of sounds inside Nex would write a preference, look like it
/// worked, and be ignored by every notification that followed.
///
/// What the OS offers instead is better than anything that list could be: any
/// ringtone or audio file on the device, plus vibration, importance, and
/// whether the notification may show on a lock screen — all in the place
/// people already look for it, and all remembered across a reinstall.
///
/// On the same channel Android already hosts, for the reason written on
/// `os_capture_bridge.dart`: a second one is one more thing to forget to
/// register.
abstract final class NexNotificationSettings {
  static const _channel = MethodChannel('nex/os_capture');

  /// Whether there is anywhere to send the user at all.
  static bool get supported => Platform.isAndroid;

  /// Opens the settings for [channelId]. False when nothing could be opened —
  /// an Android too old to have channels, or a ROM with no activity for that
  /// screen — so the caller can say so instead of leaving a row that does
  /// nothing when tapped.
  static Future<bool> open(String channelId) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openChannelSettings', {
            'channel': channelId,
          }) ??
          false;
    } on MissingPluginException {
      // No native half on this platform.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
