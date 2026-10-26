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
}
