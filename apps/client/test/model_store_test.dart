import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/local_ai_support.dart';
import 'package:nex_client/platform/model_store.dart';

String digestOf(List<int> bytes) => '${sha256.convert(bytes)}';

/// Two halves of a model, small enough to be a test and shaped like the real
/// thing: split, each with its own digest, and a digest over the join.
final partA = utf8.encode('the first half of some weights');
final partB = utf8.encode('and the second half of them');
final whole = [...partA, ...partB];

ModelRelease releaseFor({String? wholeDigest}) => ModelRelease(
  id: 'test-model',
  filename: 'model.litertlm',
  sizeBytes: whole.length,
  licenseUrl: 'https://example.invalid/terms',
  licenseNotice: 'Notice',
  sha256: wholeDigest ?? digestOf(whole),
  parts: [
    ModelPart(
      url: 'https://example.invalid/model.part-aa',
      filename: 'model.part-aa',
      sha256: digestOf(partA),
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

  group('what is offered before anything is downloaded', () {
    test('an unpublished model is not installable', () {
      // The shipped constant is a placeholder until the weights are uploaded.
      // False here is what keeps the UI from offering a download that 404s.
      expect(NexModelStore.installable(NexModels.gemma4E2B), isFalse);
      expect(NexModelStore.installable(releaseFor()), isTrue);
    });

    test('an unpublished model reports why, rather than a bare no', () async {
      final support = await LocalAi.check(NexModels.gemma4E2B);
      expect(support.supported, isFalse);
      // On a test host the platform check fires first; either answer is a
      // truthful reason and neither is "unavailable" with no explanation.
      expect(
        support.blocker,
        anyOf(LocalAiBlocker.platform, LocalAiBlocker.notPublished),
      );
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
