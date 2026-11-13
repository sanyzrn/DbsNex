import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// What targeting API 36 (Android 16) asks of the native side, held where only
/// a device would otherwise notice it going.
///
/// Declarations rather than behaviour, on purpose: predictive back and the
/// large-screen orientation rule happen in the system, and what this keeps is
/// that the app is still set up to meet them.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = XmlDocument.parse(
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
  );
  const android = 'http://schemas.android.com/apk/res/android';
  final native = [
    for (final entity in Directory(
      'android/app/src/main',
    ).listSync(recursive: true))
      if (entity is File &&
          (entity.path.endsWith('.kt') || entity.path.endsWith('.java')))
        entity,
  ];

  test('the app targets Android 16', () {
    expect(RegExp(r'targetSdk = 36\b').hasMatch(gradle), isTrue);
  });

  test('compileSdk is a number the CI installer can read, and covers the '
      'plugins and the target', () {
    // tools/install_android_ndk.sh installs this exact platform before the
    // build; `flutter.compileSdkVersion` there would leave it nothing to read.
    final compile = RegExp(
      r'^\s*compileSdk = (\d+)',
      multiLine: true,
    ).firstMatch(gradle);
    expect(compile, isNotNull);
    final level = int.parse(compile!.group(1)!);
    // flutter_local_notifications 23 compiles against API 37.
    expect(level, greaterThanOrEqualTo(37));
    final target = RegExp(r'targetSdk = (\d+)').firstMatch(gradle)!.group(1)!;
    expect(level, greaterThanOrEqualTo(int.parse(target)));
  });

  test('predictive back is opted into and nothing native intercepts back', () {
    final application = manifest.findAllElements('application').single;
    expect(
      application.getAttribute(
        'enableOnBackInvokedCallback',
        namespaceUri: android,
      ),
      'true',
    );
    // At API 36 the system no longer calls onBackPressed nor dispatches
    // KEYCODE_BACK; code relying on either would silently stop running.
    for (final file in native) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('onBackPressed')), reason: file.path);
      expect(source, isNot(contains('KEYCODE_BACK')), reason: file.path);
    }
  });

  test('no theme opts out of edge-to-edge, which API 36 no longer allows', () {
    for (final entity in Directory(
      'android/app/src/main/res',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.xml')) continue;
      expect(
        entity.readAsStringSync(),
        isNot(contains('windowOptOutEdgeToEdgeEnforcement')),
        reason: entity.path,
      );
    }
  });

  test('no large-screen compatibility opt-out stands in for real support', () {
    // Android 16 offers a temporary property that keeps the old orientation
    // behaviour; it goes away in Android 17. The app follows the device on
    // large screens instead (large_screen_test.dart).
    expect(
      manifest.toXmlString(),
      isNot(contains('PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY')),
    );
  });
}
