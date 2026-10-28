import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2.3.5: what Cafe Bazaar and Myket are given. The store build removes the
/// installer permission, and no release build allows cleartext anywhere.
void main() {
  test('the store overlay removes the installer permission', () {
    final overlay = File(
      'android/app/src/store/AndroidManifest.xml',
    ).readAsStringSync();
    expect(overlay, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(overlay, contains('tools:node="remove"'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('NEX_STORE_BUILD=true'));
    expect(gradle, contains('src/store/AndroidManifest.xml'));
  });

  test('the camera and the microphone are never required hardware', () {
    // Cafe Bazaar warned that Nex was limited to phones with a camera. The
    // permissions stay; the hardware must be optional.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final feature in [
      'android.hardware.camera',
      'android.hardware.camera.any',
      'android.hardware.camera.autofocus',
      'android.hardware.microphone',
    ]) {
      expect(
        RegExp(
          '<uses-feature[^>]*android:name="${RegExp.escape(feature)}"'
          '[^>]*android:required="false"',
        ).hasMatch(manifest),
        isTrue,
        reason: feature,
      );
    }
  });

  test('a release build allows no cleartext traffic at all', () {
    final release = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    expect(release, contains('cleartextTrafficPermitted="false"'));
    expect(release, isNot(contains('cleartextTrafficPermitted="true"')));
    // The developer's loopback exception lives in the debug build only.
    final debug = File(
      'android/app/src/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();
    expect(debug, contains('10.0.2.2'));
  });
  // An XML comment may not contain "--". The store overlay once said
  // `--dart-define` in its comment, the manifest merger refused the file, and
  // only a store build on CI found out.
  test('every Android XML file has well-formed comments', () {
    final files = Directory('android/app/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.xml'));
    expect(files, isNotEmpty);
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final comment in RegExp(
        r'<!--(.*?)-->',
        dotAll: true,
      ).allMatches(text)) {
        expect(comment.group(1), isNot(contains('--')), reason: file.path);
        expect(comment.group(1)!.endsWith('-'), isFalse, reason: file.path);
      }
    }
  });
}
