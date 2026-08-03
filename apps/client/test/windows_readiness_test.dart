import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/file_opener.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';

import 'support/in_process_db.dart';

/// The two things that stopped Nex working on the Windows target it already
/// ships an installer for.
///
/// Neither was catchable by the Windows CI job, which builds the app and never
/// runs it — a missing federated implementation is a runtime fact, not a
/// compile-time one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opening a file', () {
    test('desktop does not go through the Android-only plugin', () {
      // open_filex declares exactly two platforms in its pubspec, android and
      // ios. Every desktop call reached a channel nobody had registered, so
      // "Open" on a media note failed — and so did launching the downloaded
      // update, which meant the whole in-app updater fetched an installer it
      // could never run.
      expect(
        strategyFor(isAndroid: false, isIOS: false),
        FileOpenStrategy.shell,
        reason: 'Windows, macOS and Linux all need the shell',
      );
      expect(
        strategyFor(isAndroid: true, isIOS: false),
        FileOpenStrategy.plugin,
      );
      expect(
        strategyFor(isAndroid: false, isIOS: true),
        FileOpenStrategy.plugin,
      );
    });

    test('a path nothing can open is reported, not thrown', () async {
      // The host here is Linux, which takes the same shell branch Windows
      // does — so this exercises the real desktop path.
      final outcome = await nexOpenFile('/nonexistent/nex-test-file.bin');
      expect(outcome, FileOpenOutcome.failed);
    });
  });

  group('the OS capture bridge', () {
    late Directory tmp;
    late NexServices services;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('nex_win_');
      final dbPath = p.join(tmp.path, 'nex.sqlite');
      Directory(p.join(tmp.path, 'media')).createSync(recursive: true);
      Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
      services = NexServices.forTest(
        worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
        deviceId: 'test',
        preferences: await NexPreferences.load(),
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: dbPath,
        mediaDir: p.join(tmp.path, 'media'),
        backupDir: p.join(tmp.path, 'backups'),
      );
    });

    tearDown(() async {
      await services.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('starting is a no-op where the channel does not exist', () async {
      // `start()` awaited `invokeMethod('takePending')` unguarded. On Windows
      // nothing registers `nex/os_capture`, so it threw MissingPluginException
      // straight out of NexServices.bootstrap and into the host's
      // FutureBuilder: the app opened an error screen instead of a timeline.
      expect(OsCaptureBridge.isSupported, Platform.isAndroid);

      final bridge = OsCaptureBridge(services);
      addTearDown(bridge.dispose);
      await expectLater(bridge.start(), completes);
    });

    test('a share payload still works once handed over directly', () async {
      // `handle` is pure Dart and is what the desktop file picker feeds, so it
      // has to keep working on a platform with no channel at all.
      final bridge = OsCaptureBridge(services);
      addTearDown(bridge.dispose);

      await bridge.handle({
        'type': 'shared_text',
        'text': 'captured without a platform channel',
      });

      final notes = await services.timeline();
      expect(notes.single.content, 'captured without a platform channel');
    });

    test('picking a file off Android uses the desktop dialog', () async {
      // Not the channel: file_selector is endorsed on Windows and the image
      // picker has been using it all along. Without a mock the dialog returns
      // null, which is the "user cancelled" path — what matters is that it
      // does not throw MissingPluginException.
      if (OsCaptureBridge.isSupported) return;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/file_selector'),
            (call) async => null,
          );
      await expectLater(OsCaptureBridge.pickFile(), completion(isNull));
    });
  });
}
