import 'dart:io';

import 'package:flutter/services.dart';

/// A store Nex can be installed from, which then owns its updates.
enum NexStore { bazaar, myket }

/// Where this copy of Nex was installed from (REL-01).
///
/// Cafe Bazaar's rules say an app downloaded from Bazaar is updated only
/// through Bazaar; the in-app updater, which fetches the APK from GitHub and
/// hands it to the system installer, is exactly what they forbid. So a copy a
/// store installed never checks GitHub, and says where its updates come from
/// instead. A copy installed any other way — the GitHub release, a shared APK
/// — keeps the updater: nothing else would ever update it.
abstract final class NexInstallSource {
  static const _channel = MethodChannel('nex/os_capture');

  /// The store that installed this copy, or null for any other source.
  /// Read once at start ([load]); null until then and off Android.
  static NexStore? store;

  /// A build made for Cafe Bazaar and Myket (2.3.5): `--dart-define=
  /// NEX_STORE_BUILD=true`. Its manifest leaves out REQUEST_INSTALL_PACKAGES
  /// (see `android/app/build.gradle.kts`), because a store reviews the file
  /// it is given and both forbid an app updating itself from elsewhere — so
  /// this copy never offers to, whoever installed it.
  static const storeBuild = bool.fromEnvironment('NEX_STORE_BUILD');

  /// Whether something other than Nex keeps this copy up to date: a store
  /// installed it, or it was built for one.
  static bool get updatesFromStore => store != null || storeBuild;

  static Future<void> load() async {
    if (!Platform.isAndroid) return;
    try {
      store = fromInstaller(
        await _channel.invokeMethod<String>('installSource'),
      );
    } on MissingPluginException {
      store = null;
    } on PlatformException {
      store = null;
    }
  }

  /// The store a package installer name belongs to.
  static NexStore? fromInstaller(String? package) => switch (package) {
    'com.farsitel.bazaar' => NexStore.bazaar,
    'ir.mservices.market' => NexStore.myket,
    _ => null,
  };
}
