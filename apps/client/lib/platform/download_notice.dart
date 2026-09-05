import 'package:flutter/services.dart';

/// The update download's entry in the notification shade, and the thing that
/// keeps it running.
///
/// Those are one call because on Android they are one object. The transfer
/// itself is Dart's and already survived leaving the update screen, but it did
/// not survive leaving the app: the process is suspended shortly after the
/// last window goes away. A foreground service is what exempts it — and a
/// foreground service must post a notification of its own, so it owns the
/// progress one too. Two notifications for one download would be worse than
/// the problem.
abstract final class NexDownloadNotice {
  /// The same channel the share intent, the file picker and the previews use.
  static const _channel = MethodChannel('nex/os_capture');

  /// Shows or updates the download's notification.
  ///
  /// Answers whether the platform took the job. False means there is no
  /// service to run it — Windows, where nothing suspends the process and an
  /// ordinary notification was always all this needed — and the caller posts
  /// its own instead. False also covers a start Android refused, which is
  /// the old behaviour rather than a failure worth reporting.
  static Future<bool> show({required String title, required int percent}) =>
      _ask('downloadNotice', <String, Object>{
        'title': title,
        'percent': percent,
      });

  /// Takes it down, and lets the process be suspended again.
  static Future<bool> hide() => _ask('stopDownloadNotice', const {});

  static Future<bool> _ask(String method, Map<String, Object> arguments) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      // No native half on this platform.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
