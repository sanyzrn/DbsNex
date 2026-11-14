import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/db_worker.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// A launch that fails after the worker came up must not leave the worker
/// behind.
///
/// The worker is spawned before the recovery steps run, and the error screen
/// a failed bootstrap becomes offers "Try again" — which used to spawn a
/// second isolate beside the leaked first one, both holding the same
/// database. The failure here is injected at exactly the point the real ones
/// live (after the spawn, before the session is returned); what it proves is
/// the disposal, not the throw.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a failed launch disposes its worker; the retry starts from zero',
    () async {
      final root = Directory.systemTemp.createTempSync('nex_bootstrap_leak_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      addTearDown(() => PathProviderPlatform.instance = oldPaths);
      SharedPreferences.setMockInitialValues({'onboarding.complete': true});
      final preferences = await NexPreferences.load();
      addTearDown(preferences.dispose);

      NexServices.debugFailRecovery = true;
      addTearDown(() => NexServices.debugFailRecovery = false);
      await expectLater(
        NexServices.bootstrap(preferences: preferences),
        throwsStateError,
      );
      expect(
        NexDbWorker.debugLiveIsolates,
        0,
        reason: 'the worker the failed launch spawned is disposed with it',
      );

      // The same root, the same preferences, the library intact: "Try again"
      // has to work, and on a graph of one.
      NexServices.debugFailRecovery = false;
      final services = await NexServices.bootstrap(preferences: preferences);
      expect(NexDbWorker.debugLiveIsolates, 1);
      await services.dispose();
      expect(NexDbWorker.debugLiveIsolates, 0);
    },
  );
}
