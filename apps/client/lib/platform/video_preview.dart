import 'package:flutter/services.dart';

/// A single frame of a video, pulled out by the operating system.
///
/// The same trade as [NexPdfPreview], for the same reason. Android has had
/// `MediaMetadataRetriever` since API 10 and this app's minimum is 24, so the
/// native half is a dozen lines on the method channel the app already has.
/// Playing a video in the sheet would mean a player, a surface, and a codec
/// plugin; showing a video means one bitmap. This is the second one.
///
/// So this is Android only, deliberately, and the absence is not an error
/// anywhere: a platform with no retriever shows the file row it always showed,
/// and the file still opens in whatever does play it.
abstract final class NexVideoPreview {
  /// The same channel the share intent, the file picker and the PDF preview
  /// use. A second one would be a second thing to register and forget to
  /// register.
  static const _channel = MethodChannel('nex/os_capture');

  /// A representative frame of the video at [path] as encoded image bytes, or
  /// null when there is no frame to be had — no retriever on this platform, a
  /// file that is not a video, one in a codec the device cannot decode, a
  /// truncated download.
  ///
  /// JPEG today, and the caller does not need to know: `Image.memory` reads
  /// the header. The PDF preview beside this one answers in PNG, which is
  /// right for a page of text and wrong for a photograph — the same frame is
  /// a few hundred kilobytes one way and several megabytes the other, all of
  /// it copied across the channel to be drawn at thumbnail size.
  ///
  /// Every one of those is null rather than an exception because the caller
  /// does the same thing about all of them: shows the file and says nothing
  /// about a cover.
  ///
  /// Guarded by the catch rather than by a `Platform.isAndroid` check. The
  /// channel is the authority on whether it exists — and a platform check
  /// here would also make every caller untestable off Android, since a widget
  /// test runs on the host.
  ///
  /// [width] is in device pixels and is a bound, not a resize: the frame comes
  /// back no wider than this, and a video already narrower is left alone
  /// rather than blown up. It matters more here than it looks — a frame of a
  /// 4K video is 3840x2160, and a bitmap is four bytes a pixel, so asking for
  /// the frame at its own size is thirty-three megabytes to draw a thumbnail.
  static Future<Uint8List?> poster(String path, {int width = 1080}) async {
    if (path.isEmpty) return null;
    try {
      return await _channel
          .invokeMethod<Uint8List>('videoPreview', <String, Object>{
            'path': path,
            'width': width,
          });
    } on MissingPluginException {
      // No native half on this platform. Not a failure — an absence.
      return null;
    } on PlatformException {
      return null;
    }
  }
}
