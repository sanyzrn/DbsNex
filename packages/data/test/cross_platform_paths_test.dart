import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Windows paths in an export restore note and attachment files on POSIX',
    () async {
      // The export ZIP always uses forward slashes; database paths keep the
      // writer's host spelling. Both spellings must survive the receiving OS.
      final root = Directory.systemTemp.createTempSync('nex-foreign-paths-');
      final db = NexDatabase.open('${root.path}/nex.sqlite');
      try {
        final repo = SqliteNoteRepository(
          db,
          localDeviceId: 'android-receiver',
        );
        final at = DateTime.utc(2026).toIso8601String();
        final note = {
          'id': 'windows-file',
          'type': 'file',
          'content': 'letter.txt',
          'media_uri': r'C:\Users\Saeed\Nex\media\letter.txt',
          'media_hash': sha256OfBytes(utf8.encode('letter')),
          'created_at': at,
          'updated_at': at,
          'device_id': 'windows-source',
          'rev': 1,
          'sync_state': 'pending',
        };
        final attachment = {
          'id': 'windows-attachment',
          'note_id': 'windows-file',
          'position': 1,
          'kind': 'file',
          'media_uri': r'C:\Users\Saeed\Nex\media\invoice.txt',
          'media_hash': sha256OfBytes(utf8.encode('invoice')),
          'name': 'invoice.txt',
          'created_at': at,
          'updated_at': at,
          'device_id': 'windows-source',
          'rev': 1,
        };
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'notes.json',
              jsonEncode({
                'version': 3,
                'notes': [note],
                'attachments': [attachment],
              }),
            ),
          )
          ..addFile(ArchiveFile.string('media/letter.txt', 'letter'))
          ..addFile(ArchiveFile.string('media/invoice.txt', 'invoice'));
        final source = File('${root.path}/windows.zip')
          ..writeAsBytesSync(ZipEncoder().encode(archive));
        final result = await repo.importArchive(
          archiveFile: source,
          mediaRoot: '${root.path}/media',
        );
        expect(result.imported, 1);
        final restored = repo.getById('windows-file')!;
        expect(File(restored.mediaUri!).readAsStringSync(), 'letter');
        expect(restored.attachmentCount, 1);
        final attached = SqliteAttachmentRepository(
          repo,
          localDeviceId: 'receiver',
        ).forNote(restored.id).single;
        expect(File(attached.mediaUri).readAsStringSync(), 'invoice');
        expect(restored.deviceId, 'windows-source');
      } finally {
        db.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
