import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A Takeout export, built the way Google actually lays one out: notes under
/// `Takeout/Keep/`, an HTML copy of each beside it, and the photos.
List<int> takeoutZip() {
  final zip = Archive();
  void add(String name, List<int> bytes) =>
      zip.add(ArchiveFile.bytes(name, bytes));

  add(
    'Takeout/Keep/note-a.json',
    utf8.encode(
      jsonEncode({
        'isTrashed': false,
        'title': 'Groceries',
        'textContent': 'cooler\nplane tickets',
        'userEditedTimestampUsec': 1700000000000000,
        'labels': [
          {'name': 'Errands'},
        ],
      }),
    ),
  );
  add(
    'Takeout/Keep/note-b.json',
    utf8.encode(
      jsonEncode({
        'isTrashed': true,
        'title': '',
        'textContent': 'already deleted',
        'userEditedTimestampUsec': 1700000001000000,
      }),
    ),
  );
  add(
    'Takeout/Keep/list.json',
    utf8.encode(
      jsonEncode({
        'isTrashed': false,
        'title': 'Shopping',
        'listContent': [
          {'text': 'milk', 'isChecked': true},
          {'text': 'bread', 'isChecked': false},
        ],
        'userEditedTimestampUsec': 1700000002000000,
        'labels': [
          {'name': 'Errands'},
        ],
      }),
    ),
  );
  // A note that is a photo and one line under it — the commonest thing in
  // anybody's Keep, and the case that used to import as nothing at all.
  add(
    'Takeout/Keep/note-c.json',
    utf8.encode(
      jsonEncode({
        'isTrashed': false,
        'title': '',
        'textContent': 'the whiteboard',
        'userEditedTimestampUsec': 1700000003000000,
        'attachments': [
          {'filePath': 'photo.jpg', 'mimetype': 'image/jpeg'},
        ],
      }),
    ),
  );
  // A note pointing at a photo the export did not carry. Its words still come
  // across; the photo is counted.
  add(
    'Takeout/Keep/note-d.json',
    utf8.encode(
      jsonEncode({
        'isTrashed': false,
        'title': '',
        'textContent': 'lost its picture',
        'userEditedTimestampUsec': 1700000004000000,
        'attachments': [
          {'filePath': 'gone.jpg', 'mimetype': 'image/jpeg'},
        ],
      }),
    ),
  );
  // The duplicate HTML rendering, and the photo note-c points at. Keep nests
  // the file under the export root while the JSON names it bare, which is why
  // matching is on the last segment.
  add('Takeout/Keep/note-a.html', utf8.encode('<html>cooler</html>'));
  add('Takeout/Keep/photo.jpg', const [0xFF, 0xD8, 0xFF, 0xE0]);
  return ZipEncoder().encode(zip);
}

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late CaptureService capture;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_import_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
    capture = CaptureService(repo, deviceId: 'test');
  });

  tearDown(() {
    try {
      db.close();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) =>
      File(p.join(tmp.path, name))..writeAsBytesSync(bytes);

  test('a Takeout zip lands in the library, dates and tags intact', () {
    final result = NoteImportArchive.read(write('takeout.zip', takeoutZip()));

    // Without a media directory the photo notes still bring their words.
    expect(result.notes, hasLength(4));
    expect(result.skippedTrashed, 1);
    // The HTML twin and the photo are filtered before decompressing, so
    // neither shows up as something that could not be read.
    expect(result.unreadable, 0);

    final written = capture.importNotes(result.notes);
    expect(written, hasLength(4));

    final timeline = repo.listTimeline(limit: 50);
    expect(timeline, hasLength(4));

    final groceries = timeline.firstWhere((n) => n.title == 'Groceries');
    expect(groceries.content, 'cooler\nplane tickets');
    // The export's own date, not the moment of the import. Two thousand notes
    // all dated today is a timeline nobody can read.
    expect(
      groceries.createdAt.toUtc(),
      DateTime.fromMicrosecondsSinceEpoch(1700000000000000, isUtc: true),
    );

    final shopping = timeline.firstWhere((n) => n.type == NoteType.checklist);
    expect(shopping.checklistItems.first.done, isTrue);

    // One tag, not one per note: `upsertTag` is what merges the label.
    expect(repo.listTags().where((t) => t.name == 'Errands'), hasLength(1));
  });

  test('a bare .json outside any archive imports on its own', () {
    final file = write(
      'note.json',
      utf8.encode(jsonEncode({'title': '', 'textContent': 'a thought'})),
    );

    final result = NoteImportArchive.read(file);
    expect(capture.importNotes(result.notes), hasLength(1));
    expect(repo.listTimeline(limit: 5).single.content, 'a thought');
  });

  test('a zip that is not a zip is empty, not an error', () {
    final file = write('broken.zip', utf8.encode('this is not a zip at all'));
    expect(NoteImportArchive.read(file).notes, isEmpty);
  });

  test('a file that does not exist is empty, not an error', () {
    expect(
      NoteImportArchive.read(File(p.join(tmp.path, 'nope.zip'))).notes,
      isEmpty,
    );
  });

  test('a note dated in the future is clamped to now', () {
    final ahead = DateTime.now().toUtc().add(const Duration(days: 400));
    final written = capture.importNotes([
      ImportedNote(
        type: NoteType.text,
        text: 'from the future',
        createdAt: ahead,
      ),
    ]);

    // Otherwise it pins itself to the top of the timeline for over a year.
    expect(written.single.createdAt.isBefore(ahead), isTrue);
  });

  test('an import is pending sync, like anything else this device wrote', () {
    final written = capture.importNotes([
      const ImportedNote(type: NoteType.text, text: 'imported'),
    ]);

    expect(written.single.syncState, SyncState.pending);
    expect(written.single.rev, 1);
  });

  group('photos out of a Takeout export', () {
    test('a photo note becomes a photo note, words and all', () {
      final media = Directory(p.join(tmp.path, 'media'));
      final result = NoteImportArchive.read(
        write('takeout.zip', takeoutZip()),
        mediaInto: media,
      );

      final written = capture.importNotes(
        result.notes,
        mediaFor: NoteImportArchive.mediaPathFor,
      );
      final photo = written.firstWhere((n) => n.type == NoteType.photo);

      // The file is on disk, under a name that cannot collide with this
      // person's own captures.
      expect(photo.mediaUri, isNotNull);
      expect(File(photo.mediaUri!).existsSync(), isTrue);
      expect(p.basename(photo.mediaUri!), 'keep-photo.jpg');
      expect(File(photo.mediaUri!).readAsBytesSync(), [0xFF, 0xD8, 0xFF, 0xE0]);
      // And the line under the picture survived. A Keep note is usually both.
      expect(photo.content, 'the whiteboard');
    });

    test('a photo the export left out is counted, not invented', () {
      final result = NoteImportArchive.read(
        write('takeout.zip', takeoutZip()),
        mediaInto: Directory(p.join(tmp.path, 'media')),
      );

      // note-d points at a file the archive does not carry. Its words import
      // as text; the missing picture shows up in the number people read.
      final orphan = result.notes.firstWhere(
        (n) => n.text == 'lost its picture',
      );
      expect(orphan.type, NoteType.text);
      expect(NoteImportArchive.mediaPathFor(orphan), isNull);
      expect(result.skippedAttachments, greaterThan(0));
    });

    test('without somewhere to write, the words still import', () {
      // The path every caller took until now, and the one a test double or a
      // platform with no media directory still takes.
      final result = NoteImportArchive.read(write('takeout.zip', takeoutZip()));
      expect(result.notes.any((n) => n.text == 'the whiteboard'), isTrue);
      expect(
        result.notes.every((n) => NoteImportArchive.mediaPathFor(n) == null),
        isTrue,
      );
    });
  });
}
