import 'dart:async';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Runs before every test in this directory (Flutter's own convention for
/// this filename — no test file has to import it).
///
/// `NexPreferences.load()` now reads AI provider API keys through
/// `flutter_secure_storage`, which has no plugin registered under
/// `flutter_test` — every one of the nine test files that already call
/// `load()` would otherwise fail with a `MissingPluginException` the moment
/// this shipped, most of them nowhere near anything AI-related.
///
/// A fresh map before each test, not one shared for the whole file: the same
/// reason `SharedPreferences.setMockInitialValues({})` is called in `setUp`
/// rather than once at the top of a file — state a previous test case wrote
/// must not be what the next one reads.
///
/// The assistant's border turns for as long as the assistant is open — an
/// animation that never ends, which `pumpAndSettle` would wait on forever.
/// It holds still under test; `nex_edge_glow_test.dart` in `packages/ui`
/// covers the turning itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  NexAmbientEdgeGlow.turns = false;
  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
  });
  await testMain();
}
