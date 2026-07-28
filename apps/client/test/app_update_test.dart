import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/app_update.dart';

void main() {
  group('NexVersion', () {
    test('parses with and without the leading v', () {
      expect(NexVersion.tryParse('0.2.1').toString(), '0.2.1');
      expect(NexVersion.tryParse('v0.2.1').toString(), '0.2.1');
      expect(NexVersion.tryParse(' v0.2.1 ').toString(), '0.2.1');
    });

    test('rejects anything that is not a semantic version', () {
      for (final bad in ['v.0.2.1', '0.2', 'vX.Y.Z', '', 'latest', '01.2.3']) {
        expect(NexVersion.tryParse(bad), isNull, reason: bad);
      }
    });

    test('orders numerically, not as strings', () {
      // The whole reason this type exists: "0.10.0" < "0.9.0" as text.
      expect(
        NexVersion.tryParse('0.10.0')! > NexVersion.tryParse('0.9.0')!,
        isTrue,
      );
      expect(
        NexVersion.tryParse('1.0.0')! > NexVersion.tryParse('0.99.99')!,
        isTrue,
      );
      expect(
        NexVersion.tryParse('0.2.10')! > NexVersion.tryParse('0.2.9')!,
        isTrue,
      );
    });

    test('a pre-release sorts below the release it leads to', () {
      expect(
        NexVersion.tryParse('1.0.0')! > NexVersion.tryParse('1.0.0-beta')!,
        isTrue,
      );
      expect(
        NexVersion.tryParse('1.0.0-beta')! > NexVersion.tryParse('1.0.0')!,
        isFalse,
      );
    });

    test('equal versions are not an update', () {
      expect(
        NexVersion.tryParse('0.2.0')! > NexVersion.tryParse('0.2.0')!,
        isFalse,
      );
    });
  });

  group('UpdateChecker', () {
    late UpdateChecker checker;

    setUp(() {
      checker = UpdateChecker(currentVersion: '0.2.0', assetSuffix: '-universal.apk');
    });

    tearDown(() => checker.close());

    String release({
      required String tag,
      List<Map<String, Object?>> assets = const [
        {
          'name': 'Nex-0.3.0-universal.apk',
          'browser_download_url': 'https://example.invalid/Nex-0.3.0-universal.apk',
          'size': 42,
        },
      ],
      bool draft = false,
      bool prerelease = false,
      String? body,
    }) =>
        jsonEncode({
          'tag_name': tag,
          'draft': draft,
          'prerelease': prerelease,
          'body': body,
          'assets': assets,
        });

    UpdateCheck run(String body, {String current = '0.2.0'}) => checker.parseForTest(
          body,
          installed: NexVersion.tryParse(current)!,
          suffix: '-universal.apk',
        );

    test('offers a newer release with its asset', () {
      final result = run(release(tag: 'v0.3.0', body: 'notes here'));
      expect(result.status, UpdateStatus.available);
      expect(result.version.toString(), '0.3.0');
      expect(result.downloadUrl, endsWith('-universal.apk'));
      expect(result.sizeBytes, 42);
      expect(result.notes, 'notes here');
    });

    test('the same version is up to date', () {
      expect(run(release(tag: 'v0.2.0')).status, UpdateStatus.upToDate);
    });

    test('an older release is up to date, never a downgrade', () {
      expect(run(release(tag: 'v0.1.2')).status, UpdateStatus.upToDate);
    });

    test('drafts and pre-releases are not pushed at the user', () {
      expect(run(release(tag: 'v0.3.0', draft: true)).status, UpdateStatus.upToDate);
      expect(
        run(release(tag: 'v0.3.0', prerelease: true)).status,
        UpdateStatus.upToDate,
      );
      // Even if the flag is absent, the tag itself is enough to tell.
      expect(run(release(tag: 'v0.3.0-beta')).status, UpdateStatus.upToDate);
    });

    test('a newer release with no installable asset is not an update', () {
      final result = run(
        release(
          tag: 'v0.3.0',
          assets: [
            {
              'name': 'Nex-0.3.0-arm64-v8a.apk',
              'browser_download_url': 'https://example.invalid/split.apk',
              'size': 1,
            },
            {
              'name': 'Nex-0.3.0.aab',
              'browser_download_url': 'https://example.invalid/bundle.aab',
              'size': 1,
            },
          ],
        ),
      );
      // A split APK can be the wrong ABI and the bundle is not installable at
      // all, so neither counts.
      expect(result.status, UpdateStatus.upToDate);
    });

    test('picks the universal APK out of a full release', () {
      final result = run(
        release(
          tag: 'v0.3.0',
          assets: [
            {
              'name': 'Nex-0.3.0.aab',
              'browser_download_url': 'https://example.invalid/bundle.aab',
              'size': 1,
            },
            {
              'name': 'Nex-0.3.0-arm64-v8a.apk',
              'browser_download_url': 'https://example.invalid/split.apk',
              'size': 2,
            },
            {
              'name': 'Nex-0.3.0-universal.apk',
              'browser_download_url': 'https://example.invalid/universal.apk',
              'size': 3,
            },
          ],
        ),
      );
      expect(result.status, UpdateStatus.available);
      expect(result.downloadUrl, 'https://example.invalid/universal.apk');
    });

    test('a malformed response is unavailable, not up to date', () {
      // Reporting "you are current" when nothing was checked would be a lie.
      expect(run('not json').status, UpdateStatus.unavailable);
      expect(run('[]').status, UpdateStatus.unavailable);
      expect(run(release(tag: 'garbage')).status, UpdateStatus.unavailable);
    });
  });

  group('UpdateDownloader', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('nex_dl_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('old installers are swept before the new one lands', () async {
      // Cleanup used to be scoped to the in-flight download's own filename, so
      // every previous version — tens of megabytes each — stayed in the cache
      // directory forever.
      File('${tmp.path}/Nex-0.1.0.apk').writeAsBytesSync([1, 2, 3]);
      File('${tmp.path}/Nex-0.1.9.exe').writeAsBytesSync([1, 2, 3]);
      File('${tmp.path}/Nex-0.2.0.apk.part').writeAsBytesSync([1]);
      // Not ours, and not touched.
      File('${tmp.path}/holiday-photo.jpg').writeAsBytesSync([9]);

      final downloader = UpdateDownloader(
        client: MockClient((_) async => http.Response.bytes([4, 5, 6, 7], 200)),
      );
      addTearDown(downloader.close);

      await downloader.download(
        url: 'https://example.invalid/Nex-0.3.0.apk',
        into: tmp,
        filename: 'Nex-0.3.0.apk',
      );

      final left = tmp
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toSet();
      expect(left, {'Nex-0.3.0.apk', 'holiday-photo.jpg'});
    });
  });
}
