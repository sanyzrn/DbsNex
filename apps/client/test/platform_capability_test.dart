import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_client/platform/media_picker_impl.dart';
import 'package:nex_core/nex_core.dart';

/// Platform-support smoke tests.
///
/// The Windows CI job used to only build the app. Plugin availability is a
/// runtime concern, so a missing federated implementation (just_audio had no
/// Windows endorsement; image_picker still has none) produced a green build and
/// a MissingPluginException crash in the shipped installer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an audio player can be constructed on this platform', () {
    expect(AudioPlayer.new, returnsNormally);
  });

  test('media picker declares camera support only where it exists', () {
    final picker = PlatformMediaPicker();
    final expectCamera = Platform.isAndroid || Platform.isIOS;

    expect(picker.supportsCamera, expectCamera);
    expect(picker.supportsGallery, isTrue);
  });

  test('media picker satisfies the core port', () {
    expect(PlatformMediaPicker(), isA<MediaPicker>());
  });
}
