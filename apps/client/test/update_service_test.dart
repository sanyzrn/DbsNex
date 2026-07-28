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
          'browser_download_url': 'https://example.invalid/Nex-$next-universal.apk',
          'size': size ?? 4,
        },
      ],
    });
  }

  UpdateService build({
    required MockClient client,
    String? assetSuffix,
  }) =>
      UpdateService(
        preferences: preferences,
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

  test('a second launch inside the interval does not touch the network',
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
  });

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

  test('turning the automatic check off stops it, but force still works',
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
  });

  test('an installer already on disk is not fetched twice', () async {
    final current = NexVersion.tryParse(nexAppVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    File(p.join(tmp.path, 'Nex-$next.apk')).writeAsBytesSync([1, 2, 3, 4]);

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

  test('a half-written file from a previous run is replaced, not trusted',
      () async {
    final current = NexVersion.tryParse(nexAppVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    // Right name, wrong length: an interrupted download must not be handed to
    // the installer as if it were whole.
    File(p.join(tmp.path, 'Nex-$next.apk')).writeAsBytesSync([9]);

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
  });

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
}
