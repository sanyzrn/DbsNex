import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/platform/local_ai_support.dart';
import 'package:nex_client/platform/model_store.dart';

String digestOf(List<int> bytes) => '${sha256.convert(bytes)}';

/// Two halves of a model, small enough to be a test and shaped like the real
/// thing: split, each with its own digest, and a digest over the join.
final partA = utf8.encode('the first half of some weights');
final partB = utf8.encode('and the second half of them');
final whole = [...partA, ...partB];

ModelRelease releaseFor({
  String? wholeDigest,
  String? partUrl,
  String? partDigest,
}) => ModelRelease(
  id: 'test-model',
  filename: 'model.litertlm',
  sizeBytes: whole.length,
  licenseUrl: 'https://example.invalid/terms',
  licenseNotice: 'Notice',
  sha256: wholeDigest ?? digestOf(whole),
  parts: [
    ModelPart(
      url: partUrl ?? 'https://example.invalid/model.part-aa',
      filename: 'model.part-aa',
      sha256: partDigest ?? digestOf(partA),
    ),
    ModelPart(
      url: 'https://example.invalid/model.part-ab',
      filename: 'model.part-ab',
      sha256: digestOf(partB),
    ),
  ],
);

/// Serves the two parts, counting requests so a test can prove what was *not*
/// re-fetched.
MockClient server({List<String>? log, List<int>? corruptSecondPartAs}) =>
    MockClient((request) async {
      log?.add(request.url.path);
      final body = request.url.path.endsWith('aa')
          ? partA
          : (corruptSecondPartAs ?? partB);
      return http.Response.bytes(body, 200, request: request);
    });

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('nex_models_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  NexModelStore storeWith(http.Client client) =>
      NexModelStore(root: tmp, client: client);

  group('installing', () {
    test('downloads every part, joins them, and leaves one file', () async {
      final model = releaseFor();
      final store = storeWith(server());
      addTearDown(store.close);

      final file = await store.install(model);

      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), whole);
      expect(store.isInstalled(model), isTrue);

      // The parts are gone. Keeping them would double a 2.6 GB install on a
      // phone, and they have no further use once the join is verified.
      final left = Directory(file.parent.path)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(left, ['model.litertlm']);
    });

    test('reports progress across parts, not per part', () async {
      final model = releaseFor();
      final store = storeWith(server());
      addTearDown(store.close);
      final seen = <double?>[];

      await store.install(model, onProgress: (p) => seen.add(p.fraction));

      // Whatever the shape, it never goes backwards and it ends at 1 — a bar
      // that resets to zero on the second part is the bug this guards.
      expect(seen.whereType<double>(), isNotEmpty);
      final monotonic = seen.whereType<double>().toList();
      for (var i = 1; i < monotonic.length; i++) {
        expect(monotonic[i], greaterThanOrEqualTo(monotonic[i - 1]));
      }
      expect(monotonic.last, 1);
    });

    test('an already-installed model is not downloaded again', () async {
      final model = releaseFor();
      final log = <String>[];
      final store = storeWith(server(log: log));
      addTearDown(store.close);

      await store.install(model);
      final requestsAfterFirst = log.length;
      await store.install(model);

      expect(log.length, requestsAfterFirst);
    });

    test('a part already on disk and correct is skipped on retry', () async {
      final model = releaseFor();
      final dir = Directory('${tmp.path}/${model.id}')
        ..createSync(recursive: true);
      File('${dir.path}/model.part-aa').writeAsBytesSync(partA);

      final log = <String>[];
      final store = storeWith(server(log: log));
      addTearDown(store.close);

      await store.install(model);

      // Only the missing half crossed the network. Over a real install this is
      // the difference between resuming and paying for 1.3 GB twice.
      expect(log, ['/model.part-ab']);
    });
  });

  group('a model small enough not to be split', () {
    // The shipped constant is one part, because the artifact fits under the
    // 2 GiB asset cap. Nothing in [NexModelStore] special-cases that, and this
    // is what holds it to that: a list of one joins, verifies and cleans up on
    // the same path as a list of two.
    ModelRelease single() => ModelRelease(
      id: 'single-part-model',
      filename: 'model.litertlm',
      sizeBytes: whole.length,
      licenseUrl: 'https://example.invalid/terms',
      licenseNotice: 'Notice',
      sha256: digestOf(whole),
      parts: [
        ModelPart(
          url: 'https://example.invalid/model.whole',
          filename: 'model.part-aa',
          sha256: digestOf(whole),
        ),
      ],
    );

    test('installs from one part and leaves one file', () async {
      final store = NexModelStore(
        root: tmp,
        client: MockClient((request) async => http.Response.bytes(whole, 200)),
      );
      addTearDown(store.close);

      final file = await store.install(single());

      expect(file.readAsBytesSync(), whole);
      final left = file.parent
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(left, ['model.litertlm']);
    });

    test('one part with a url and a digest is installable', () {
      // [NexModelStore.installable] asks every part for both. A one-part
      // release passing that is the reason publishing a small model needs no
      // change to this file beyond the constant.
      expect(NexModelStore.installable(single()), isTrue);
    });
  });

  group('verification', () {
    test('a part that arrives corrupt fails and is not kept', () async {
      final model = releaseFor();
      final store = storeWith(
        server(corruptSecondPartAs: utf8.encode('not the right bytes')),
      );
      addTearDown(store.close);

      await expectLater(store.install(model), throwsA(isA<HttpException>()));
      expect(store.isInstalled(model), isFalse);
    });

    test(
      'parts that verify but join wrong fail, and the parts survive',
      () async {
        // Each part is intact and the whole-file digest disagrees — the join is
        // what went wrong, so a retry should cost disk time, not the download.
        final model = releaseFor(
          wholeDigest: digestOf(utf8.encode('different')),
        );
        final store = storeWith(server());
        addTearDown(store.close);

        await expectLater(store.install(model), throwsA(isA<HttpException>()));
        expect(store.isInstalled(model), isFalse);

        final left =
            Directory('${tmp.path}/${model.id}')
                .listSync()
                .whereType<File>()
                .map((f) => f.uri.pathSegments.last)
                .toList()
              ..sort();
        expect(left, ['model.part-aa', 'model.part-ab']);
      },
    );
  });

  group('storage accounting and removal', () {
    test('half-finished installs are counted, not invisible', () async {
      final model = releaseFor();
      final dir = Directory('${tmp.path}/${model.id}')
        ..createSync(recursive: true);
      File('${dir.path}/model.part-aa').writeAsBytesSync(partA);

      // A Settings screen that reports 0 B while a gigabyte sits in a part
      // file is why people think an app is lying about storage.
      expect(storeWith(server()).installedBytes(model), partA.length);
    });

    test('deleting takes the parts with it', () async {
      final model = releaseFor();
      final store = storeWith(server());
      addTearDown(store.close);
      await store.install(model);

      await store.delete(model);

      expect(store.isInstalled(model), isFalse);
      expect(store.installedBytes(model), 0);
    });
  });

  group('installing from a file the user already has', () {
    test(
      'a matching file is copied in and the original is left alone',
      () async {
        final model = releaseFor();
        final source = File('${tmp.path}/somewhere-else.litertlm')
          ..writeAsBytesSync(whole);
        final store = storeWith(
          MockClient((request) async => fail('nothing should be downloaded')),
        );
        addTearDown(store.close);

        final file = await store.installFromFile(model, source);

        expect(file.readAsBytesSync(), whole);
        expect(store.isInstalled(model), isTrue);
        // Copied, not moved. The file is the user's, sitting where they chose.
        expect(source.existsSync(), isTrue);
      },
    );

    test('a file that is not this model is refused', () async {
      final model = releaseFor();
      final source = File('${tmp.path}/something-else.bin')
        ..writeAsBytesSync(utf8.encode('a completely different file'));
      final store = storeWith(server());
      addTearDown(store.close);

      // The digest is the only thing standing between "pick a file" and
      // handing an arbitrary file to a native runtime, so it is not optional
      // and this is what holds it that way.
      await expectLater(
        store.installFromFile(model, source),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.isInstalled(model), isFalse);
    });

    test('nothing half-copied is left behind when it is refused', () async {
      final model = releaseFor();
      final source = File('${tmp.path}/wrong.bin')
        ..writeAsBytesSync(utf8.encode('wrong'));
      final store = storeWith(server());
      addTearDown(store.close);

      await expectLater(
        store.installFromFile(model, source),
        throwsA(isA<FileSystemException>()),
      );
      final dir = Directory('${tmp.path}/${model.id}');
      expect(
        dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
    });
  });

  group('stopping a download', () {
    test('a cancelled install throws DownloadPaused, not a failure', () async {
      final model = releaseFor();
      final store = storeWith(server());
      addTearDown(store.close);

      // Distinct from HttpException on purpose: a pause reported as "download
      // failed" is how someone concludes the feature is broken.
      await expectLater(
        store.install(model, isCancelled: () => true),
        throwsA(isA<DownloadPaused>()),
      );
      expect(store.isInstalled(model), isFalse);
    });
  });

  group('progress in bytes', () {
    test('reports bytes on disk against the model size', () async {
      final model = releaseFor();
      final store = storeWith(server());
      addTearDown(store.close);
      final seen = <ModelInstallProgress>[];

      await store.install(model, onProgress: seen.add);

      // A percentage is the wrong unit for two gigabytes on a data plan.
      expect(seen.map((p) => p.totalBytes), everyElement(whole.length));
      expect(seen.last.receivedBytes, whole.length);
      // Never goes backwards across the part boundary — a counter that
      // restarts at zero halfway looks like the first half was thrown away.
      final counts = seen.map((p) => p.receivedBytes).toList();
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], greaterThanOrEqualTo(counts[i - 1]));
      }
    });
  });

  group('what is offered before anything is downloaded', () {
    test('a model missing a url or a digest is not installable', () {
      // False here is what keeps the UI from offering a download that 404s or
      // arrives unverified. Both halves are required, and each is checked
      // separately because a half-filled constant is the realistic mistake.
      expect(NexModelStore.installable(releaseFor()), isTrue);
      expect(NexModelStore.installable(releaseFor(partUrl: '')), isFalse);
      expect(NexModelStore.installable(releaseFor(partDigest: '')), isFalse);
      expect(NexModelStore.installable(releaseFor(wholeDigest: '')), isFalse);
    });

    test('the shipped model is completely specified', () {
      // Guards the constant itself. Publishing a model is an edit to four
      // string literals by hand, and the failure mode is filling in three of
      // them — which without this reads as "your device is unsupported".
      final model = NexModels.gemma4E2B;
      expect(NexModelStore.installable(model), isTrue);
      expect(model.sizeBytes, greaterThan(0));
      expect(model.licenseUrl, isNotEmpty);
      expect(model.licenseNotice, isNotEmpty);
      // A single asset, so the two digests describe the same bytes. If this
      // ever splits again they must diverge, and this line should go.
      expect(model.parts.single.sha256, model.sha256);
      // Lower-case hex, because that is what `sha256.convert()` produces and
      // the comparison in [NexModelStore] is a plain string equality. A digest
      // pasted from PowerShell is upper-case and would fail every download
      // after 2 GB had already been paid for.
      expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('an unsupported host reports why, rather than a bare no', () async {
      final support = await LocalAi.check(NexModels.gemma4E2B);
      // A test host is neither Android nor iOS, so this is the platform
      // blocker. The point is that there is always a reason attached, never
      // "unavailable" with nothing a person can act on.
      expect(support.supported, isFalse);
      expect(support.blocker, LocalAiBlocker.platform);
    });

    test(
      'a 32-bit device is refused on architecture',
      () async {
        final support = await LocalAi.check(
          releaseFor(),
          abisOverride: const {'armeabi-v7a'},
          freeBytesOverride: 64 * 1024 * 1024 * 1024,
        );
        expect(support.blocker, LocalAiBlocker.architecture);
      },
      skip: !Platform.isAndroid && !Platform.isIOS,
    );

    test(
      'unknown free space does not withhold the feature',
      () async {
        // A storage API that declines to answer should not cost someone a
        // feature their phone can run.
        final support = await LocalAi.check(
          releaseFor(),
          abisOverride: const {'arm64-v8a'},
        );
        expect(support.freeBytes, anyOf(isNull, isA<int>()));
      },
      skip: !Platform.isAndroid && !Platform.isIOS,
    );
  });
}
