import 'dart:io';

import 'package:flutter/services.dart';

/// Why a capture did not make it into the library.
///
/// Photo capture used to wrap everything in `catch (_)` and show one sentence —
/// "capture could not be stored" — for at least four unrelated causes, with no
/// action attached. The user's only recourse was to guess which one it was and
/// try the same thing again. Three of these four are things they can actually
/// do something about, but only if the app says which one happened.
enum CaptureFailure {
  /// The OS refused the camera or the photo library.
  permission,

  /// The device has no room for the copy.
  storage,

  /// The picked file could not be read back — a cloud placeholder that never
  /// downloaded, or a file removed between picking and reading.
  unreadable,

  /// Anything else, including a failed database write.
  unknown;

  /// Classifies what was actually thrown.
  ///
  /// Deliberately narrow: each branch keys off something the platform really
  /// sets, so a case that cannot be told apart honestly reports [unknown]
  /// rather than guessing at a cause and sending the user after the wrong fix.
  static CaptureFailure of(Object error) {
    if (error is PlatformException) {
      // image_picker reports refusals as `camera_access_denied` and
      // `photo_access_denied`.
      if (error.code.endsWith('access_denied')) return permission;
      return unknown;
    }
    if (error is FileSystemException) {
      // ENOSPC. The one errno worth naming: it is the only common failure the
      // user can clear themselves, and "out of space" is useless advice when
      // it is wrong.
      if (error.osError?.errorCode == 28) return storage;
      return unreadable;
    }
    return unknown;
  }
}
