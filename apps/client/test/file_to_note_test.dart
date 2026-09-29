import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// A shared text file becomes a note in place: same item, same tags, now
/// editable words. Only Markdown was allowed through here before.
void main() {
  late Directory tmp;
  late NexServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_file_note_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a text file note becomes a text note with its words', () async {
    final file = File(p.join(services.mediaDir, 'x.txt'))
      ..writeAsStringSync('خرید\r\nنان و شیر');
    final note = await services.captureFile(
      mediaUri: file.path,
      mediaHash: 'h',
      originalFilename: 'list.txt',
      mimeType: 'text/plain',
    );
    await services.convertMarkdown(note);
    final converted = (await services.worker.getById(note.id))!;
    expect(converted.type, NoteType.text);
    expect(converted.content, 'خرید\nنان و شیر');
    expect(converted.mediaUri, isNull);
  });

  test('a file with no readable words is left exactly as it was', () async {
    final file = File(p.join(services.mediaDir, 'x.docx'))
      ..writeAsBytesSync(utf8.encode('not a document'));
    final note = await services.captureFile(
      mediaUri: file.path,
      mediaHash: 'h',
      originalFilename: 'broken.docx',
    );
    await expectLater(services.convertMarkdown(note), throwsStateError);
    final unchanged = (await services.worker.getById(note.id))!;
    expect(unchanged.type, NoteType.file);
    expect(unchanged.mediaUri, file.path);
  });
}
