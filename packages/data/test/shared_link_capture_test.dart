import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

/// A browser shares a page as text. It used to land as a text note holding
/// the address; it is captured as a link note now, with any words around the
/// address kept as its caption.
void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db, localDeviceId: 'phone');
  });
  tearDown(() => db.close());

  test('a shared address becomes a link note', () {
    final note = repo.captureShared({
      'requestId': 'r-1',
      'type': 'shared_text',
      'text': 'https://example.com/a',
    })!;
    expect(note.type, NoteType.link);
    expect(note.linkUrl, 'https://example.com/a');
    expect(note.caption, isNull);
  });

  test('a title shared with the address is the link note\'s caption', () {
    final note = repo.captureShared({
      'requestId': 'r-2',
      'type': 'shared_text',
      'text': 'A good article\nhttps://example.com/a',
    })!;
    expect(note.type, NoteType.link);
    expect(note.caption, 'A good article');
  });

  test('ordinary shared text is still a text note', () {
    final note = repo.captureShared({
      'requestId': 'r-3',
      'type': 'shared_text',
      'text': 'buy milk',
    })!;
    expect(note.type, NoteType.text);
    expect(note.content, 'buy milk');
  });

  test('a recovered typed draft that is an address stays a text note', () {
    final note = repo.captureShared({
      'requestId': 'draft-1',
      'type': 'shared_text',
      'text': 'https://example.com/a',
    })!;
    expect(note.type, NoteType.text);
  });
}
