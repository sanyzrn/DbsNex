import 'package:flutter/services.dart';

/// The window a share arrives through, when it is the invisible one.
///
/// Sharing into Nex used to open Nex — a launch screen over whatever app you
/// were using, a timeline you did not ask for, and a gesture to get back out.
/// A share now lands on `ShareActivity` instead: translucent, with no starting
/// window, closed as soon as the note is written.
///
/// Two calls, because the flow has two moments. [isSilent] is asked before a
/// single frame is drawn, so the app knows to draw nothing at all. [done] is
/// the end of it: what to say, and permission to close.
abstract final class NexShareWindow {
  /// The same channel the share intent, the file picker and the previews use.
  static const _channel = MethodChannel('nex/os_capture');

  /// Whether this launch is the invisible share window.
  ///
  /// False everywhere else, including on a platform with no native half —
  /// which is the honest answer there, since without one there is no
  /// `ShareActivity` and every launch is the app itself.
  static Future<bool> isSilent() => _ask('isShareWindow', const {});

  /// Says what happened to the share, and closes the window.
  ///
  /// A toast rather than anything drawn in the app, because by design there is
  /// no app on screen to draw it in, and because it has to outlive the window
  /// by a couple of seconds. The text is passed in rather than looked up on
  /// the platform: Nex's language is a preference of its own, and Android only
  /// knows the device's.
  ///
  /// Answers whether the window actually closed. False means this was the
  /// ordinary app after all, and whatever was going to be shown on screen
  /// still has to be.
  static Future<bool> done(String message) =>
      _ask('shareDone', <String, Object>{'message': message});

  static Future<bool> _ask(String method, Map<String, Object> arguments) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
