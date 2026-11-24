/// Where a piece of media came from.
enum MediaSource { camera, gallery }

/// What a kept media file turned out to be.
enum CapturedMediaKind { image, video }

/// A file the user chose or captured.
class CapturedMedia {
  const CapturedMedia({
    required this.path,
    required this.name,
    this.mimeType,
    this.kind = CapturedMediaKind.image,
  });

  final String path;
  final String name;
  final String? mimeType;

  /// The kind the file's own bytes confirmed. A picker's claim about a name
  /// is not enough: a PDF named `.jpg` is still a PDF.
  final CapturedMediaKind kind;

  bool get isVideo => kind == CapturedMediaKind.video;

  /// The same file, once its kind is known.
  CapturedMedia asKind(CapturedMediaKind kind) =>
      CapturedMedia(path: path, name: name, mimeType: mimeType, kind: kind);
}

/// Platform-capability port for media capture.
///
/// image_picker has no endorsed Windows implementation, and Windows is a
/// first-class v1 target. Without a capability abstraction each screen had to
/// remember to branch on Platform.is* checks, and a missed branch produced a
/// MissingPluginException at the exact moment the user tried to capture.
///
/// UI code must read [supportsCamera] / [supportsGallery] and never inspect the
/// platform directly.
abstract interface class MediaPicker {
  bool get supportsCamera;

  bool get supportsGallery;

  /// Returns null when the user cancels.
  Future<CapturedMedia?> pickImage(MediaSource source);

  /// Photos and videos together, several at once — the system's own media
  /// picker, as a chat app opens it. Empty when the user cancels.
  ///
  /// What comes back is still only a claim about each file: callers verify
  /// [CapturedMedia] with its bytes before keeping it.
  Future<List<CapturedMedia>> pickMedia();
}
