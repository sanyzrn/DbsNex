import 'package:flutter/services.dart';

/// Whether the operating system is allowed to capture what this window shows.
///
/// There is no Flutter-side answer to this. The recents thumbnail and a
/// screenshot are both taken by the system, from outside the app, off a frame
/// the app never draws — so nothing painted in Dart can hide from either.
/// Android's `FLAG_SECURE` is the switch that can, and it lives on the
/// Activity's window.
///
/// Wired to the app lock rather than always on. Someone who never asked for a
/// lock has not asked to lose screenshots either, and the same reasoning
/// already decides whether reminders show their text on the lock screen (see
/// `NexServices`, `hideOnLockScreen`). Turning the lock on is the moment the
/// user says these notes are private, and it is the moment this comes on with
/// it — including the recents thumbnail, which is the copy of the timeline
/// that a lock screen otherwise does nothing about.
abstract final class NexSecureWindow {
  /// The same channel the share intent, the file picker and the previews use.
  /// A second one would be a second thing to register and forget to register.
  static const _channel = MethodChannel('nex/os_capture');

  /// Asks the platform to start or stop blocking capture of this window.
  ///
  /// Guarded by the catch rather than by a `Platform.isAndroid` check, for the
  /// reason the video preview gives: the channel is the authority on
  /// whether a native half exists, and a platform check would make every
  /// caller untestable off Android, since a widget test runs on the host.
  ///
  /// A platform that cannot do this is an absence, not a failure — Windows has
  /// no equivalent flag, and the app lock still locks. So nothing is thrown
  /// back at the caller, whose only alternative would be to ignore it.
  static Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', <String, Object>{
        'on': on,
      });
    } on MissingPluginException {
      // No native half on this platform.
    } on PlatformException {
      // A window that would not take the flag. Nothing the caller can do.
    }
  }
}
