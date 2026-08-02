import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';

/// Platform adapter for the [MediaPicker] port.
///
/// image_picker has no endorsed Windows implementation — camera capture and the
/// system gallery picker are Android/iOS/web concepts. The repository carried
/// both image_picker and file_selector but no capability abstraction, so every
/// screen had to remember to branch on Platform.is* checks. A missed branch
/// produced a MissingPluginException at the exact moment the user tried to
/// capture.
///
/// The UI must read [supportsCamera] / [supportsGallery] rather than checking
/// the platform itself.
class PlatformMediaPicker implements MediaPicker {
  PlatformMediaPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _imageGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'],
  );

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool get supportsCamera => _isMobile;

  @override
  bool get supportsGallery => true;

  @override
  Future<CapturedMedia?> pickImage(MediaSource source) async {
    if (source == MediaSource.camera && supportsCamera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      return shot == null
          ? null
          : CapturedMedia(path: shot.path, name: shot.name);
    }

    if (_isMobile) {
      final shot = await _picker.pickImage(source: ImageSource.gallery);
      return shot == null
          ? null
          : CapturedMedia(path: shot.path, name: shot.name);
    }

    // Desktop: file_selector is the supported path on Windows and Linux.
    final file = await openFile(acceptedTypeGroups: const [_imageGroup]);
    return file == null
        ? null
        : CapturedMedia(path: file.path, name: file.name);
  }
}
