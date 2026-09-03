import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
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

    test('a number too large for an int is no update, not a crash', () {
      // The pattern's `\d*` matches a digit run of any length, so these all
      // reached `int.parse` and threw a FormatException straight out of a
      // method whose entire contract is that it answers null instead. The
      // input is a tag from a remote server: one mistyped release would have
      // broken the update check for every install until it was renamed.
      for (final huge in [
        'v99999999999999999999.0.0',
        '1.99999999999999999999.0',
        '1.0.99999999999999999999',
      ]) {
        expect(NexVersion.tryParse(huge), isNull, reason: huge);
      }

      // The largest value that does fit still parses — the guard is about
      // overflow, not about long-looking numbers.
      expect(NexVersion.tryParse('9223372036854775807.0.0'), isNotNull);
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
      checker = UpdateChecker(
        currentVersion: '0.2.0',
        assetSuffix: '-universal.apk',
      );
    });

    tearDown(() => checker.close());

    String release({
      required String tag,
      List<Map<String, Object?>> assets = const [
        {
          'name': 'Nex-0.3.0-universal.apk',
          'browser_download_url':
              'https://example.invalid/Nex-0.3.0-universal.apk',
          'size': 42,
        },
      ],
      bool draft = false,
      bool prerelease = false,
      String? body,
    }) => jsonEncode({
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': body,
      'assets': assets,
    });

    UpdateCheck run(String body, {String current = '0.2.0'}) =>
        checker.parseForTest(
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
      expect(
        run(release(tag: 'v0.3.0', draft: true)).status,
        UpdateStatus.upToDate,
      );
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

  group('Android ABI matches its own split, not the universal APK', () {
    test('each running ABI maps to the split the release workflow builds', () {
      expect(androidAbiSuffixForTest(Abi.androidArm64), '-arm64-v8a.apk');
      expect(androidAbiSuffixForTest(Abi.androidArm), '-armeabi-v7a.apk');
      expect(androidAbiSuffixForTest(Abi.androidX64), '-x86_64.apk');
    });

    test(
      'an ABI the release workflow does not split for falls back to universal',
      () {
        // 32-bit x86 (the emulator's IA32) has no split built for it.
        expect(androidAbiSuffixForTest(Abi.androidIA32), '-universal.apk');
      },
    );

    test('a release with the matching split skips the universal APK', () {
      final checker = UpdateChecker(currentVersion: '0.2.0');
      final result = checker.parseForTest(
        jsonEncode({
          'tag_name': 'v0.3.0',
          'draft': false,
          'prerelease': false,
          'body': null,
          'assets': [
            {
              'name': 'Nex-0.3.0-universal.apk',
              'browser_download_url': 'https://example.invalid/universal.apk',
              'size': 90000000,
            },
            {
              'name': 'Nex-0.3.0-arm64-v8a.apk',
              'browser_download_url': 'https://example.invalid/arm64.apk',
              'size': 30000000,
            },
          ],
        }),
        installed: NexVersion.tryParse('0.2.0')!,
        suffix: '-arm64-v8a.apk',
        fallbackSuffix: '-universal.apk',
      );
      checker.close();
      expect(result.status, UpdateStatus.available);
      expect(result.downloadUrl, 'https://example.invalid/arm64.apk');
      expect(result.assetName, 'Nex-0.3.0-arm64-v8a.apk');
      expect(result.sizeBytes, 30000000);
    });

    test(
      'a release built without that split still offers the universal APK',
      () {
        final checker = UpdateChecker(currentVersion: '0.2.0');
        final result = checker.parseForTest(
          jsonEncode({
            'tag_name': 'v0.3.0',
            'draft': false,
            'prerelease': false,
            'body': null,
            'assets': [
              {
                'name': 'Nex-0.3.0-universal.apk',
                'browser_download_url': 'https://example.invalid/universal.apk',
                'size': 90000000,
              },
            ],
          }),
          installed: NexVersion.tryParse('0.2.0')!,
          suffix: '-arm64-v8a.apk',
          fallbackSuffix: '-universal.apk',
        );
        checker.close();
        // Without the fallback this would report upToDate — see the sibling
        // test in the plain 'UpdateChecker' group above, which asserts
        // exactly that for a suffix with no fallback at all.
        expect(result.status, UpdateStatus.available);
        expect(result.downloadUrl, 'https://example.invalid/universal.apk');
      },
    );
  });

  group('UpdateChecker.check() resolves a checksum', () {
    // parseForTest exercises `_parse` synchronously and cannot see the
    // SHA256SUMS follow-up fetch, which only happens inside `check()` — so
    // these run the whole thing over a mocked http.Client instead.
    String releaseWithSums({String? sumsLine}) => jsonEncode({
      'tag_name': 'v0.3.0',
      'draft': false,
      'prerelease': false,
      'body': null,
      'assets': [
        {
          'name': 'Nex-0.3.0-universal.apk',
          'browser_download_url':
              'https://example.invalid/Nex-0.3.0-universal.apk',
          'size': 4,
        },
        if (sumsLine != null)
          {
            'name': 'SHA256SUMS',
            'browser_download_url': 'https://example.invalid/SHA256SUMS',
          },
      ],
    });

    test('fetches SHA256SUMS and matches the asset by name', () async {
      final digest = sha256.convert(utf8.encode('installer bytes')).toString();
      final checker = UpdateChecker(
        currentVersion: '0.2.0',
        assetSuffix: '-universal.apk',
        client: MockClient((request) async {
          if (request.url.path.endsWith('SHA256SUMS')) {
            return http.Response(
              'deadbeef  Nex-0.2.9-universal.apk\n'
              '$digest  Nex-0.3.0-universal.apk\n',
              200,
            );
          }
          return http.Response(releaseWithSums(sumsLine: digest), 200);
        }),
      );
      addTearDown(checker.close);

      final result = await checker.check();

      expect(result.status, UpdateStatus.available);
      expect(result.checksumSha256, digest);
    });

    test('no SHA256SUMS asset means no checksum, not a failure', () async {
      final checker = UpdateChecker(
        currentVersion: '0.2.0',
        assetSuffix: '-universal.apk',
        client: MockClient((_) async => http.Response(releaseWithSums(), 200)),
      );
      addTearDown(checker.close);

      final result = await checker.check();

      expect(result.status, UpdateStatus.available);
      expect(result.checksumSha256, isNull);
    });

    test('a failed checksum fetch does not block the update', () async {
      final checker = UpdateChecker(
        currentVersion: '0.2.0',
        assetSuffix: '-universal.apk',
        client: MockClient((request) async {
          if (request.url.path.endsWith('SHA256SUMS')) {
            return http.Response('server error', 500);
          }
          return http.Response(releaseWithSums(sumsLine: 'irrelevant'), 200);
        }),
      );
      addTearDown(checker.close);

      final result = await checker.check();

      expect(result.status, UpdateStatus.available);
      expect(result.checksumSha256, isNull);
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

      final left = tmp.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(left, {'Nex-0.3.0.apk', 'holiday-photo.jpg'});
    });

    test('an interrupted download resumes from the partial file', () async {
      // Reported symptom: a network blip, or just leaving the app, dropped
      // the connection partway through and the next attempt started over
      // from zero — tens of megabytes paid for twice. The `.part` a previous
      // attempt left behind is no longer deleted on sight; it is asked for
      // by Range instead, and only the missing tail crosses the network.
      File('${tmp.path}/Nex-0.3.0.apk.part').writeAsBytesSync([1, 2, 3]);

      String? rangeSent;
      final downloader = UpdateDownloader(
        client: MockClient((request) async {
          rangeSent = request.headers['range'];
          return http.Response.bytes(
            [4, 5, 6, 7],
            206,
            headers: {'content-range': 'bytes 3-6/7'},
          );
        }),
      );
      addTearDown(downloader.close);

      final result = await downloader.download(
        url: 'https://example.invalid/Nex-0.3.0.apk',
        into: tmp,
        filename: 'Nex-0.3.0.apk',
      );

      expect(rangeSent, 'bytes=3-');
      expect(result.readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7]);
      expect(File('${tmp.path}/Nex-0.3.0.apk.part').existsSync(), isFalse);
    });

    test(
      'a partial past the end of the real file is dropped, not resumed',
      () async {
        // The .part is longer than the asset actually is — left over from a
        // different release under the same name, or corrupted — so the range
        // requested is unsatisfiable (416). That is a reason to start over,
        // not to keep the stale bytes already on disk.
        File(
          '${tmp.path}/Nex-0.3.0.apk.part',
        ).writeAsBytesSync([9, 9, 9, 9, 9]);

        var requests = 0;
        final downloader = UpdateDownloader(
          client: MockClient((request) async {
            requests++;
            if (request.headers.containsKey('range')) {
              return http.Response('', 416);
            }
            return http.Response.bytes([1, 2, 3, 4], 200);
          }),
        );
        addTearDown(downloader.close);

        final result = await downloader.download(
          url: 'https://example.invalid/Nex-0.3.0.apk',
          into: tmp,
          filename: 'Nex-0.3.0.apk',
        );

        expect(requests, 2);
        expect(result.readAsBytesSync(), [1, 2, 3, 4]);
      },
    );

    test('a matching checksum is accepted', () async {
      final bytes = [1, 2, 3, 4];
      final digest = sha256.convert(bytes).toString();
      final downloader = UpdateDownloader(
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      addTearDown(downloader.close);

      final result = await downloader.download(
        url: 'https://example.invalid/Nex-0.3.0.apk',
        into: tmp,
        filename: 'Nex-0.3.0.apk',
        expectedSha256: digest,
      );

      expect(result.readAsBytesSync(), bytes);
    });

    test(
      'a mismatched checksum is rejected and the file is not left behind',
      () async {
        // A right-length, wrong-content download — corrupted in transit, or a
        // release whose asset does not match what SHA256SUMS says — must not
        // reach the installer under either name.
        final downloader = UpdateDownloader(
          client: MockClient(
            (_) async => http.Response.bytes([1, 2, 3, 4], 200),
          ),
        );
        addTearDown(downloader.close);

        await expectLater(
          downloader.download(
            url: 'https://example.invalid/Nex-0.3.0.apk',
            into: tmp,
            filename: 'Nex-0.3.0.apk',
            expectedSha256: '0' * 64,
          ),
          throwsA(isA<HttpException>()),
        );

        expect(File('${tmp.path}/Nex-0.3.0.apk').existsSync(), isFalse);
        expect(File('${tmp.path}/Nex-0.3.0.apk.part').existsSync(), isFalse);
      },
    );
  });
}
