/// Where a piece of media came from.
enum MediaSource { camera, gallery }

/// A file the user chose or captured.
class CapturedMedia {
  const CapturedMedia({required this.path, required this.name});

  final String path;
  final String name;
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
}
