import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/app_version.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/update_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late NexPreferences preferences;
  var now = DateTime(2026, 7, 28, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
    tmp = Directory.systemTemp.createTempSync('nex_update_');
    now = DateTime(2026, 7, 28, 12);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A release newer than whatever this build is, so the test does not have to
  /// be edited every time the app's version moves.
  String newerRelease({int? size}) {
    final current = NexVersion.tryParse(nexAppVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    return jsonEncode({
      'tag_name': 'v$next',
      'draft': false,
      'prerelease': false,
      'body': 'notes',
      'assets': [
        {
          'name': 'Nex-$next-universal.apk',
          'browser_download_url':
              'https://example.invalid/Nex-$next-universal.apk',
          'size': size ?? 4,
        },
      ],
    });
  }

  UpdateService build({
    required MockClient client,
    String? assetSuffix,
    void Function(NexDownloadStatus)? onDownloadStatus,
  }) => UpdateService(
        preferences: preferences,
        onDownloadStatus: onDownloadStatus,
        checker: UpdateChecker(
          currentVersion: nexAppVersion,
          client: client,
          assetSuffix: assetSuffix ?? '-universal.apk',
        ),
        downloader: UpdateDownloader(client: client),
        directory: () async => tmp,
        now: () => now,
      );

  MockClient serving(String releaseJson, {List<int>? file, int? calls}) =>
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(releaseJson, 200);
        }
        return http.Response.bytes(file ?? [1, 2, 3, 4], 200);
      });

  group('what the notification shade is told', () {
    test('a download reports progress and then that it is done', () async {
      final seen = <NexDownloadStatus>[];
      final service = build(
        client: serving(newerRelease()),
        onDownloadStatus: seen.add,
      );
      addTearDown(service.dispose);

      await service.check();
      await service.prefetching;

      expect(seen, isNotEmpty);
      expect(seen.last.stage, NexDownloadStage.done);
      // Never the same percent twice: the download reports progress far
      // faster than anything should be asked to redraw, and a notification
      // rewritten on every chunk is a platform channel used as a firehose.
      final percents = [
        for (final status in seen)
          if (status.stage == NexDownloadStage.running) status.percent,
      ];
      expect(percents, percents.toSet().toList());
    });

    test('a download that fails says it stopped, not that it finished', () async {
      final seen = <NexDownloadStatus>[];
      final service = build(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(newerRelease(), 200);
          }
          throw const SocketException('no route to host');
        }),
        onDownloadStatus: seen.add,
      );
      addTearDown(service.dispose);

      await service.check();
      await service.prefetching;

      expect(seen.last.stage, NexDownloadStage.stopped);
      // And the reason is kept rather than swallowed — the screen draws its
      // "stopped" line from exactly this.
      expect(service.downloadError, isNotNull);
      // The progress survives too, so a resume does not look like a restart.
      expect(service.downloaded, isNull);
    });
  });

  test('an available update is found and pre-downloaded', () async {
    final service = build(client: serving(newerRelease()));
    addTearDown(service.dispose);

    await service.check();
    // The download is fire-and-forget in production; here it is awaited so the
    // assertion is about the outcome, not about timing.
    await service.prefetching;

    expect(service.hasUpdate, isTrue);
    expect(service.available!.downloadUrl, endsWith('-universal.apk'));
    expect(service.downloaded, isNotNull);
    expect(service.downloaded!.existsSync(), isTrue);
  });

  test(
    'a second launch inside the interval does not touch the network',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (request.url.host == 'api.github.com') {
          return http.Response(newerRelease(), 200);
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final service = build(client: client);
      addTearDown(service.dispose);

      await service.maybeCheck();
      await service.prefetching;
      final afterFirst = requests;
      expect(afterFirst, greaterThan(0));

      // Same day: nothing.
      now = now.add(const Duration(hours: 5));
      await service.maybeCheck();
      expect(requests, afterFirst);

      // Past the interval: it looks again.
      now = now.add(const Duration(hours: 20));
      await service.maybeCheck();
      expect(requests, greaterThan(afterFirst));
    },
  );

  test('a failed check does not count as checked', () async {
    // Recording the time after a failure would suppress the next 24 hours of
    // attempts over one flaky moment.
    final service = build(
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    addTearDown(service.dispose);

    await service.maybeCheck();

    expect(preferences.lastUpdateCheck, isNull);
    expect(service.hasUpdate, isFalse);
  });

  test(
    'turning the automatic check off stops it, but force still works',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (request.url.host == 'api.github.com') {
          return http.Response(newerRelease(), 200);
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final service = build(client: client);
      addTearDown(service.dispose);

      await preferences.setAutoUpdateCheck(false);
      await service.maybeCheck();
      expect(requests, 0);

      // The button in Settings is a force, and must still work.
      await service.maybeCheck(force: true);
      expect(requests, greaterThan(0));
    },
  );

  test('an installer already on disk is not fetched twice', () async {
    final current = NexVersion.tryParse(nexAppVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    File(
      p.join(tmp.path, nexInstallerFilename(NexVersion.tryParse(next)!)),
    ).writeAsBytesSync([1, 2, 3, 4]);

    var downloads = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(newerRelease(), 200);
      }
      downloads++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    });
    final service = build(client: client);
    addTearDown(service.dispose);

    await service.check();
    await service.prefetching;

    expect(downloads, 0, reason: 'the same file is already there');
    expect(service.downloaded, isNotNull);
  });

  test(
    'a half-written file from a previous run is replaced, not trusted',
    () async {
      final current = NexVersion.tryParse(nexAppVersion)!;
      final next = '${current.major}.${current.minor}.${current.patch + 1}';
      // Right name, wrong length: an interrupted download must not be handed to
      // the installer as if it were whole.
      File(
        p.join(tmp.path, nexInstallerFilename(NexVersion.tryParse(next)!)),
      ).writeAsBytesSync([9]);

      var downloads = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(newerRelease(size: 4), 200);
        }
        downloads++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final service = build(client: client);
      addTearDown(service.dispose);

      await service.check();
      await service.prefetching;

      expect(downloads, 1);
      expect(service.downloaded!.lengthSync(), 4);
    },
  );

  test('no update means no dot', () async {
    final service = build(
      client: serving(
        jsonEncode({
          'tag_name': 'v0.0.1',
          'draft': false,
          'prerelease': false,
          'assets': <Object>[],
        }),
      ),
    );
    addTearDown(service.dispose);

    await service.check();

    expect(service.hasUpdate, isFalse);
    expect(service.downloaded, isNull);
    // A completed check still counts, so it will not run again immediately.
    expect(preferences.lastUpdateCheck, isNotNull);
  });

  test('a finished download is announced exactly once', () async {
    // The transfer belongs to the service, so it now usually completes while
    // the user is on some other screen — which is only useful if something
    // says so, and only bearable if it says so once.
    final service = build(client: serving(newerRelease()));
    addTearDown(service.dispose);

    await service.check();
    await service.prefetching;

    expect(service.downloaded, isNotNull);
    expect(service.hasUnannouncedDownload, isTrue);
    service.markAnnounced();
    expect(service.hasUnannouncedDownload, isFalse);
  });

  test('an installer found on disk at launch is not announced', () async {
    // It did not arrive during this session; a toast for it would be a
    // notification about the past.
    final current = NexVersion.tryParse(nexAppVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    File(
      p.join(tmp.path, nexInstallerFilename(NexVersion.tryParse(next)!)),
    ).writeAsBytesSync([1, 2, 3, 4]);

    final service = build(client: serving(newerRelease()));
    addTearDown(service.dispose);

    await service.check();
    await service.prefetching;

    expect(service.downloaded, isNotNull);
    expect(service.hasUnannouncedDownload, isFalse);
  });

  test(
    'ensureDownloaded joins the running fetch rather than starting another',
    () async {
      var downloads = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(newerRelease(), 200);
        }
        downloads++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final service = build(client: client);
      addTearDown(service.dispose);

      await service.check();
      // Two callers, one transfer: this is what stops the update screen pulling
      // the same bytes down a second time when it opens mid-prefetch.
      await Future.wait([
        service.ensureDownloaded(),
        service.ensureDownloaded(),
      ]);

      expect(downloads, 1);
      expect(service.isDownloading, isFalse);
      expect(service.downloadProgress, isNull);
    },
  );

  group('a download the operating system stopped', () {
    /// Everything except the interruption itself, which a `MockClient` cannot
    /// stage: it answers with whole responses, and what an interrupted
    /// transfer leaves behind is a half-written `.part`. So the first fetch is
    /// made to fail, the partial is written the way a stopped one would have
    /// left it, and what is tested is the part that was missing — whether
    /// anything picks it up again.
    Future<UpdateService> stalled({
      required MockClient client,
      List<int> alreadyHave = const [1, 2, 3],
    }) async {
      final service = build(client: client);
      addTearDown(service.dispose);
      await service.check();
      await service.prefetching;
      final version = service.available!.version!;
      if (alreadyHave.isNotEmpty) {
        File(
          p.join(tmp.path, '${nexInstallerFilename(version)}.part'),
        ).writeAsBytesSync(alreadyHave);
      }
      return service;
    }

    test('is resumed by range, not fetched again from zero', () async {
      var failFile = true;
      String? rangeAsked;
      final service = await stalled(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(newerRelease(size: 8), 200);
          }
          if (failFile) throw const SocketException('screen went off');
          rangeAsked = request.headers[HttpHeaders.rangeHeader];
          return http.Response.bytes(
            [4, 5, 6, 7, 8],
            206,
            headers: {'content-range': 'bytes 3-7/8'},
          );
        }),
      );
      failFile = false;

      // What coming back to the app now does.
      await service.resumeInterruptedDownload();
      await service.prefetching;

      // By range: the three bytes already on disk are not paid for twice.
      // On a 60 MB installer that difference is the whole point.
      expect(rangeAsked, 'bytes=3-');
      expect(service.downloaded, isNotNull);
      expect(service.downloaded!.readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('with nothing half-finished, nothing is started', () async {
      // The other side of the rule. Coming back to the app is not a request
      // to fetch an installer — it is a chance to finish one that was already
      // under way. Without the partial there is nothing under way.
      var fileRequests = 0;
      final service = await stalled(
        alreadyHave: const [],
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(newerRelease(size: 8), 200);
          }
          fileRequests++;
          throw const SocketException('screen went off');
        }),
      );
      final before = fileRequests;

      await service.resumeInterruptedDownload();
      await service.prefetching;

      expect(fileRequests, before, reason: 'nothing to resume, so nothing to do');
      expect(service.downloaded, isNull);
    });
  });
}
