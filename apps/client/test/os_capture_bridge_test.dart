import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _FakeNativeSide() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'takePending':
              final value = pending;
              pending = null;
              return value;
            default:
              return null;
          }
        });
  }

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
    native = _FakeNativeSide();
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
}
