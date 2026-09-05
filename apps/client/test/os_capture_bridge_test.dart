import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';

import 'support/in_process_db.dart';

/// The native half keeps one slot, `pending`, and `enqueue` writes to it for
/// every payload — including the ones it pushes live to a Dart side that is
/// already listening. Only `takePending` ever clears it.
///
/// So a live push handled the capture and left a copy behind, and the next
/// `start()` in the same process picked that copy up and captured it again.
/// That is not a rare path: restoring a backup calls
/// `NexRestartScope.restart()`, which builds a new bridge and starts it in the
/// same process and the same Activity.
///
/// This models the native side rather than mocking one call at a time, because
/// what is being tested is the protocol between the two: who is allowed to
/// consider a payload delivered.
class _FakeNativeSide {
  _FakeNativeSide(this.cacheDir) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'takePending':
              final value = pending;
              pending = null;
              return value;
            case 'copyShared':
              // What `copyUri` does: read the provider's stream through to a
              // file in the cache and answer where it landed. Modelled rather
              // than stubbed, because the point of the split is *when* this
              // runs — a payload refused on its declared size must never
              // reach it at all.
              final uri = (call.arguments as Map<Object?, Object?>)['uri'] as String?;
              final source = uri == null ? null : File(Uri.parse(uri).path);
              if (source == null || !source.existsSync()) return null;
              final copy = File(
                p.join(
                  cacheDir.path,
                  '${DateTime.now().microsecondsSinceEpoch}-'
                      '${p.basename(source.path)}',
                ),
              );
              await source.copy(copy.path);
              copied.add(copy.path);
              return copy.path;
            default:
              return null;
          }
        });
  }

  /// Where the copies land, standing in for `cacheDir/shared`.
  final Directory cacheDir;

  /// Every file this side has been asked to copy out, in order.
  final copied = <String>[];

  static const _channel = MethodChannel('nex/os_capture');

  /// Exactly the field `MainActivity.enqueue` writes.
  Map<String, String>? pending;
  final calls = <String>[];

  /// What `enqueue(value, live = true)` does: queue it *and* push it.
  Future<void> shareLive(Map<String, String> payload) async {
    pending = payload;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(
            MethodCall('onOsCapture', payload),
          ),
          // No reply wanted. `setMockMethodCallHandler` (outbound) and this
          // (inbound) are separate maps on the same channel, which is what
          // lets one fake stand in for both halves of the native side.
          null,
        );
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late InProcessDb db;
  late NexServices services;
  late _FakeNativeSide native;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_os_capture_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    db = InProcessDb(dbPath: dbPath, deviceId: 'test');
    services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    native = _FakeNativeSide(Directory(p.join(tmp.path, 'cache'))..createSync());
  });

  tearDown(() async {
    native.dispose();
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a live share is captured once, not once per restart', () async {
    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    await bridge.start();

    await native.shareLive({'type': 'shared_text', 'text': 'from another app'});
    expect(await db.timeline(limit: 50), hasLength(1));

    // What a backup restore does: dispose the graph and start a new bridge,
    // same process. Before the acknowledgement this replayed the payload the
    // native side was still holding and made a second, identical note.
    final second = OsCaptureBridge(services);
    addTearDown(second.dispose);
    await second.start();

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1), reason: 'one share, one note');
    expect(notes.single.content, 'from another app');
  });

  test('a share queued before Dart was listening is still captured', () async {
    // The other direction, and the reason the slot exists at all: a cold
    // start from a share intent queues without pushing, and `start()` has to
    // pick it up. Acknowledging a live push must not break this.
    native.pending = {'type': 'shared_text', 'text': 'queued before launch'};

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    await bridge.start();

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'queued before launch');
  });

  test('starting where there is no native half does not throw', () async {
    // `start()` no longer checks `Platform.isAndroid` — the channel is the
    // authority, which is what makes every case above reachable on a host.
    // The Windows failure that check was standing in for has to stay fixed:
    // an unguarded `takePending` threw out of `NexServices.bootstrap` and the
    // app opened an error screen instead of a timeline.
    native.dispose();

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    await expectLater(bridge.start(), completes);
    expect(await db.timeline(limit: 50), isEmpty);
  });

  test('a shared file is never read into memory to be captured', () async {
    // The report: a 2 GB video shared into Nex, and the next launch showed
    // "Nex could not open your local library … Out of Memory".
    //
    // `handle` read the whole file with `readAsBytes`, handed that same list
    // to `writeAsBytes`, then made a second full copy with
    // `Uint8List.fromList` for the hash — four gigabytes of peak for a
    // two-gigabyte share, and the bytes existed only to be hashed.
    //
    // Allocating a real 2 GB file here would reproduce the bug by causing it,
    // which is no use in a suite. What is asserted instead is the property
    // that makes size irrelevant: the note's hash matches the file's, and the
    // copy on disk matches byte for byte — both of which hold only if the
    // path was streamed rather than buffered.
    final source = File(p.join(tmp.path, 'clip.mp4'));
    // Not uniform: a hash over a run of identical bytes would match a
    // different-length run of them too, so it could not tell a truncated
    // stream from a complete one.
    final content = Uint8List.fromList(
      List<int>.generate(512 * 1024, (i) => (i * 31 + 7) % 256),
    );
    await source.writeAsBytes(content, flush: true);

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    await bridge.start();

    await bridge.handle({
      'type': 'shared_file',
      'uri': Uri.file(source.path).toString(),
      'filename': 'clip.mp4',
      'mimeType': 'video/mp4',
      'size': '${content.length}',
    });

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    final note = notes.single;
    expect(note.type, NoteType.file);
    expect(note.content, 'clip.mp4');

    // The hash is the note's identity for dedup, so a wrong one is worse than
    // none — and an empty one would make every unreadable attachment look
    // like the same attachment.
    expect(note.mediaHash, isNotNull);
    expect(note.mediaHash, isNotEmpty);
    expect(note.mediaHash, sha256OfBytes(content));

    // And the copy really is the file, not a truncated stream.
    final stored = File(note.mediaUri!);
    expect(stored.existsSync(), isTrue);
    expect(stored.lengthSync(), content.length);
    expect(stored.readAsBytesSync(), content);
  });

  test('a file over the limit is refused, by name and size', () async {
    // Nex is a notes app. An attachment is not stored once: the automatic
    // backup zips the whole media directory and keeps five of them, so a
    // file costs its own size plus up to five times again, and every backup
    // after it is larger for good. A shared 2 GB video came to roughly
    // fourteen gigabytes by that arithmetic.
    // A small limit rather than a hundred-megabyte file: what is being
    // tested is the rule, and a case that writes 100 MB to prove it is a case
    // people stop running.
    const limit = 4096;
    final source = File(p.join(tmp.path, 'huge.mp4'));
    await source.writeAsBytes(Uint8List(limit + 1), flush: true);

    final bridge = OsCaptureBridge(services, maxAttachmentBytes: limit);
    addTearDown(bridge.dispose);
    RejectedShare? seen;
    bridge.onRejected = (r) => seen = r;
    await bridge.start();

    await bridge.handle({
      'type': 'shared_file',
      'uri': Uri.file(source.path).toString(),
      'filename': 'huge.mp4',
      'mimeType': 'video/mp4',
      'size': '${limit + 1}',
    });

    expect(await db.timeline(limit: 50), isEmpty, reason: 'nothing captured');

    // The message names the file and its size, so the refusal reads as a
    // rule rather than as the app being broken.
    expect(seen, isNotNull);
    expect(seen!.filename, 'huge.mp4');
    expect(seen!.bytes, greaterThan(limit));
    expect(seen!.limit, limit, reason: 'the message names the rule in force');

    // The point of the whole split, and what the report was about: the file
    // is refused on what the provider said about it, before a byte moves.
    // Copying first and measuring after was correct and unusable — refusing
    // a two-gigabyte video took as long as accepting one, with the app
    // apparently frozen for all of it.
    expect(native.copied, isEmpty, reason: 'refused without being fetched');
    expect(native.calls, isNot(contains('copyShared')));

    // And nothing happened to what the person actually shared. Nex only ever
    // deletes copies it made itself, and here it made none.
    expect(source.existsSync(), isTrue);
  });

  test('a refusal during launch waits for someone to tell', () async {
    // A share can be the intent that launched the app, in which case `start`
    // drains it during bootstrap with nothing on screen yet. `takeRejection`
    // is how the timeline collects what it missed — the same shape as the
    // reminder launch path's `takeLaunchNoteId`.
    const limit = 4096;
    final source = File(p.join(tmp.path, 'huge.bin'));
    await source.writeAsBytes(Uint8List(limit + 1), flush: true);
    native.pending = {
      'type': 'shared_file',
      'uri': Uri.file(source.path).toString(),
      'filename': 'huge.bin',
      'size': '${limit + 1}',
    };

    final bridge = OsCaptureBridge(services, maxAttachmentBytes: limit);
    addTearDown(bridge.dispose);
    // Nobody listening, exactly as during bootstrap.
    await bridge.start();

    expect(await db.timeline(limit: 50), isEmpty);
    final refused = bridge.takeRejection();
    expect(refused, isNotNull);
    expect(refused!.filename, 'huge.bin');
    // Once. A second screen must not repeat a message the first one showed.
    expect(bridge.takeRejection(), isNull);
  });

  test('a file inside the limit is kept, and its cache copy is not', () async {
    // The boundary from the other side, and the cache cleanup on the success
    // path: `copyUri` writes every share into `cacheDir/shared` before Dart
    // sees it, and nothing deleted it — so each share cost twice what it
    // kept until Android reclaimed the cache.
    final source = File(p.join(tmp.path, 'small.pdf'));
    final content = Uint8List.fromList(
      List<int>.generate(4096, (i) => (i * 7 + 3) % 256),
    );
    await source.writeAsBytes(content, flush: true);

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    RejectedShare? seen;
    bridge.onRejected = (r) => seen = r;
    await bridge.start();

    await bridge.handle({
      'type': 'shared_file',
      'uri': Uri.file(source.path).toString(),
      'filename': 'small.pdf',
      'mimeType': 'application/pdf',
      'size': '${content.length}',
    });

    expect(seen, isNull, reason: 'well inside the limit');
    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'small.pdf');

    // Kept where the library keeps media, and gone from the cache.
    expect(File(notes.single.mediaUri!).readAsBytesSync(), content);
    expect(native.copied, hasLength(1), reason: 'inside the limit, so fetched');
    expect(File(native.copied.single).existsSync(), isFalse);

    // The original is the user's own file behind a content URI. It is not
    // Nex's to delete, and it never was.
    expect(source.existsSync(), isTrue);
  });

  test('a file the picker already copied is handled by its path', () async {
    // The other shape a payload arrives in, and the reason `path` is still
    // read. `ACTION_OPEN_DOCUMENT` hands back a copy in the cache before its
    // result ever reaches Dart, so there is no URI left to defer and nothing
    // to gain by asking for one. The same limit applies, measured off the
    // copy instead of off what a provider claimed.
    final picked = File(p.join(tmp.path, 'from-picker.pdf'));
    final content = Uint8List.fromList(
      List<int>.generate(2048, (i) => (i * 11 + 5) % 256),
    );
    await picked.writeAsBytes(content, flush: true);

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);
    await bridge.start();

    await bridge.handle({
      'type': 'shared_file',
      'path': picked.path,
      'filename': 'from-picker.pdf',
      'mimeType': 'application/pdf',
    });

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'from-picker.pdf');
    expect(File(notes.single.mediaUri!).readAsBytesSync(), content);
    // Nothing was fetched — there was nothing to fetch — and the picker's own
    // cache copy is cleared up, which is the case it always covered.
    expect(native.calls, isNot(contains('copyShared')));
    expect(picked.existsSync(), isFalse);
  });
}
