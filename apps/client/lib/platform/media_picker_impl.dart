import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

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
    : _picker = picker ?? ImagePicker() {
    _useSystemPhotoPicker();
  }

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

  /// Android 15 and below keep the legacy `ACTION_GET_CONTENT` picker unless
  /// this is on, and that picker happily hands over a PDF or a ZIP when asked
  /// for media. The system photo picker shows one gallery of photos and videos
  /// and nothing else — the experience WhatsApp and Telegram open. Android 16
  /// uses it regardless; older versions use it when Google Play services has
  /// the backported module, which image_picker declares in its manifest.
  ///
  /// Set here, in the app's one media adapter, before any pick runs. Setting
  /// it also affects the few screens that still ask image_picker directly for
  /// a single photo (the profile picture, a vault photo, a receipt): they get
  /// the same system picker instead of a document browser.
  static void _useSystemPhotoPicker() {
    if (!Platform.isAndroid) return;
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) {
      platform.useAndroidPhotoPicker = true;
    }
  }

  @override
  Future<CapturedMedia?> pickImage(MediaSource source) async {
    if (source == MediaSource.camera && supportsCamera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      return shot == null ? null : _captured(shot);
    }

    if (_isMobile) {
      final shot = await _picker.pickImage(source: ImageSource.gallery);
      return shot == null ? null : _captured(shot);
    }

    // Desktop: file_selector is the supported path on Windows and Linux.
    final file = await openFile(acceptedTypeGroups: const [_imageGroup]);
    return file == null ? null : _captured(file);
  }

  @override
  Future<List<CapturedMedia>> pickMedia() async {
    // One system picker for both kinds, several at a time. The kind carried
    // here is provisional — the caller checks each file's bytes before it is
    // stored (see `nexFilterMedia`).
    final shots = await _picker.pickMultipleMedia();
    return [for (final shot in shots) _captured(shot)];
  }

  static CapturedMedia _captured(XFile file) => CapturedMedia(
    path: file.path,
    // XFile's own name splits on the platform separator only, so a path the
    // picker built with `/` on Windows kept its folder in the name. The path's
    // last segment is the file's name everywhere.
    name: p.basename(file.path),
    mimeType: file.mimeType,
  );
}
