import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/capture_failure.dart';

/// Photo capture used to wrap everything in `catch (_)` and report four
/// unrelated causes as one sentence with no action attached. Three of the four
/// are things the user can fix — but only if the app says which happened.
void main() {
  test('a refused camera or photo library is a permission problem', () {
    // The codes image_picker actually raises.
    for (final code in ['camera_access_denied', 'photo_access_denied']) {
      expect(
        CaptureFailure.of(PlatformException(code: code)),
        CaptureFailure.permission,
      );
    }
  });

  test('ENOSPC is out of space, and nothing else is', () {
    expect(
      CaptureFailure.of(
        const FileSystemException('write', '/x', OSError('No space', 28)),
      ),
      CaptureFailure.storage,
    );
    // A different errno must not be reported as a full disk: "free up space"
    // is useless advice when it is wrong.
    expect(
      CaptureFailure.of(
        const FileSystemException('read', '/x', OSError('No such file', 2)),
      ),
      CaptureFailure.unreadable,
    );
  });

  test('an unclassifiable failure says so rather than guessing', () {
    expect(CaptureFailure.of(StateError('db closed')), CaptureFailure.unknown);
    expect(
      CaptureFailure.of(PlatformException(code: 'multiple_request')),
      CaptureFailure.unknown,
    );
  });
}
