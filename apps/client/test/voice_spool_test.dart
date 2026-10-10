import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/voice_spool.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

/// One ADTS frame: a 7-byte header naming 44.1 kHz and the frame's length,
/// then [payload] bytes of stand-in audio.
List<int> adtsFrame({int payload = 100}) {
  final length = 7 + payload;
  return [
    0xFF, 0xF1, //
    (1 << 6) | (4 << 2), // AAC LC, 44.1 kHz (index 4)
    (1 << 6) | ((length >> 11) & 0x03), // mono
    (length >> 3) & 0xFF,
    ((length & 0x07) << 5) | 0x1F,
    0xFC,
    ...List<int>.filled(payload, 0x21),
  ];
}

/// A memo the app died in the middle of is kept, not swept (DATA-04).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the length of a stream is its frames, a cut-off one included', () {
    final whole = [for (var i = 0; i < 43; i++) ...adtsFrame()];
    // 43 frames × 1024 samples at 44.1 kHz ≈ 998 ms.
    expect(NexVoiceSpool.adtsDurationMs(Uint8List.fromList(whole)), 998);
    // The process died mid-frame: that frame is not counted.
    final cut = [...whole, ...adtsFrame().sublist(0, 20)];
    expect(NexVoiceSpool.adtsDurationMs(Uint8List.fromList(cut)), 998);
    expect(NexVoiceSpool.adtsDurationMs(Uint8List(0)), 0);
  });

  group('on the next launch', () {
    late Directory tmp;
    late InProcessDb db;
    late NexServices services;
    late String mediaDir;
    const channel = MethodChannel('nex/os_capture');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('nex_voice_spool_');
      final dbPath = p.join(tmp.path, 'nex.sqlite');
      mediaDir = p.join(tmp.path, 'media');
      Directory(mediaDir).createSync();
      db = InProcessDb(dbPath: dbPath, deviceId: 'test');
      services = NexServices.forTest(
        worker: db,
        deviceId: 'test',
        preferences: await NexPreferences.load(),
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: dbPath,
        mediaDir: mediaDir,
        backupDir: p.join(tmp.path, 'backups'),
      );
      // The native repackaging: here, a copy.
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'remuxVoice') return null;
        final args = call.arguments as Map;
        await File(args['from'] as String).copy(args['to'] as String);
        return true;
      });
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await services.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File spool(String name, {required Duration age}) {
      final file = File(p.join(mediaDir, name))
        ..writeAsBytesSync([for (var i = 0; i < 43; i++) ...adtsFrame()]);
      file.setLastModifiedSync(DateTime.now().subtract(age));
      return file;
    }

    test('an interrupted recording becomes a voice note', () async {
      final left = spool('voice-1.recording', age: const Duration(minutes: 5));

      expect(await services.recoverVoiceRecordings(), 1);

      final note = (await db.timeline()).single;
      expect(note.type, NoteType.voice);
      expect(note.mediaUri, p.join(mediaDir, 'voice-1.m4a'));
      expect(note.durationMs, 998);
      expect(File(note.mediaUri!).existsSync(), isTrue);
      expect(left.existsSync(), isFalse);
      // Kept once: a second launch finds nothing left to recover.
      expect(await services.recoverVoiceRecordings(), 0);
    });

    test('one still being written is left alone', () async {
      final live = spool('voice-2.recording', age: Duration.zero);
      expect(await services.recoverVoiceRecordings(), 0);
      expect(live.existsSync(), isTrue);
      expect(await db.timeline(), isEmpty);
    });

    test('without the native half the stream itself is kept', () async {
      messenger.setMockMethodCallHandler(channel, null);
      spool('voice-3.recording', age: const Duration(minutes: 5));
      expect(await services.recoverVoiceRecordings(), 1);
      expect(
        (await db.timeline()).single.mediaUri,
        p.join(mediaDir, 'voice-3.aac'),
      );
    });
  });
}
