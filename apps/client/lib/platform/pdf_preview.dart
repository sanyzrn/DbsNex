import 'package:flutter/services.dart';

/// The first page of a PDF, rendered by the operating system.
///
/// Android has drawn PDFs itself since API 21 — `android.graphics.pdf` — and
/// this app's minimum is 24, so the whole of the native half is a few lines
/// on the method channel the app already has. Every Flutter PDF package ships
/// its own copy of PDFium instead: several megabytes in the APK to do what the
/// platform already does, on a screen that only ever wanted one thumbnail.
///
/// So this is Android only, deliberately, and the absence is not an error
/// anywhere: a platform with no renderer shows the file row it always showed,
/// and the file still opens in whatever does handle it.
abstract final class NexPdfPreview {
  /// The same channel the share intent and the file picker use. A second one
  /// would be a second thing to register and forget to register.
  static const _channel = MethodChannel('nex/os_capture');

  /// The first page of the PDF at [path] as PNG bytes, or null when there is
  /// no preview to be had — no renderer on this platform, a file that is not
  /// a PDF, an encrypted one, an empty one.
  ///
  /// Every one of those is null rather than an exception because the caller
  /// does the same thing about all of them: shows the file and says nothing
  /// about a preview.
  ///
  /// Guarded by the catch rather than by a `Platform.isAndroid` check. The
  /// channel is the authority on whether it exists — and a platform check
  /// here would also make every caller untestable off Android, since a widget
  /// test runs on the host.
  /// [width] and [maxHeight] are device pixels, and [maxHeight] is why this
  /// is cheap: only the top band of the page is drawn, because only the top
  /// band is shown. A full A4 at this width is around 1200x1700, and a bitmap
  /// is four bytes a pixel — eight megabytes to produce a thumbnail.
  ///
  /// Fixed rather than measured from the layout. The numbers are generous for
  /// the band the sheet shows on any phone, and threading a real measurement
  /// down would mean knowing the widget's width before it has been laid out.
  static Future<Uint8List?> firstPage(
    String path, {
    int width = 1200,
    int maxHeight = 960,
  }) async {
    if (path.isEmpty) return null;
    try {
      return await _channel
          .invokeMethod<Uint8List>('pdfPreview', <String, Object>{
            'path': path,
            'width': width,
            'maxHeight': maxHeight,
          });
    } on MissingPluginException {
      // No native half on this platform. Not a failure — an absence.
      return null;
    } on PlatformException {
      return null;
    }
  }
}
