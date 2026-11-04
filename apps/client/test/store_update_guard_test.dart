import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/update_service.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/platform/install_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final store in [
    NexStore.bazaar,
    NexStore.myket,
    if (NexInstallSource.storeBuild) null,
  ]) {
    test(
      'store $store blocks every direct updater entry point and cached consent',
      () async {
        final root = Directory.systemTemp.createTempSync('nex-store-guard-');
        addTearDown(() {
          root.deleteSync(recursive: true);
          NexInstallSource.store = null;
        });
        SharedPreferences.setMockInitialValues({
          'update.available': jsonEncode({
            'version': '999.0.0',
            'url': 'https://example.invalid/update.apk',
            'sha256': 'a' * 64,
          }),
          'update.approvedVersion': '999.0.0',
        });
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response('', 500);
        });
        NexInstallSource.store = store;
        final service = UpdateService(
          preferences: await NexPreferences.load(),
          checker: UpdateChecker(currentVersion: '2.6.4', client: client),
          downloader: UpdateDownloader(client: client),
          directory: () async => root,
        );
        addTearDown(service.dispose);
        expect(service.hasUpdate, isFalse);
        await service.check();
        await service.maybeCheck(force: true);
        await service.ensureDownloaded();
        await service.resumeInterruptedDownload();
        expect(requests, 0);
        expect(root.listSync(), isEmpty);
      },
    );
  }
}
