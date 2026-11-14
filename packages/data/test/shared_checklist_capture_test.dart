import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

/// The capture sheet's words become a list when it closes, and that
/// conversion arrives here rather than through `captureChecklist` so the
/// receipt covers it: a settle that was interrupted after the commit — the
/// reply lost, the close tried again — must find the list it already made
/// instead of making a second one. This file pins that contract.
void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db, localDeviceId: 'phone');
  });
  tearDown(() => db.close());

  Note? submit(String requestId, String body) => repo.captureShared({
    'requestId': requestId,
    'type': 'checklist',
    'body': body,
  });

  test('a checklist payload becomes a checklist note with its items', () {
    final note = submit('checklist-1', '- [ ] milk\n- [x] bread')!;
    expect(note.type, NoteType.checklist);
    expect(note.checklistItems.map((i) => i.text), ['milk', 'bread']);
    expect(note.checklistItems.map((i) => i.done), [false, true]);
  });

  test('plain lines become unticked items, none dropped', () {
    final note = submit('checklist-2', 'milk\nbread')!;
    expect(note.checklistItems.map((i) => i.text), ['milk', 'bread']);
    expect(note.checklistItems.every((i) => !i.done), isTrue);
  });

  test('the same request makes the same list, once', () {
    final first = submit('checklist-3', '- [ ] milk')!;
    final again = submit('checklist-3', '- [ ] milk')!;
    expect(again.id, first.id);
    final lists = repo
        .listTimeline(limit: 50)
        .where((n) => n.type == NoteType.checklist)
        .toList();
    expect(lists, hasLength(1));
  });

  test('an empty body is refused, not an empty note', () {
    expect(() => submit('checklist-4', ''), throwsArgumentError);
    expect(repo.listTimeline(limit: 50), isEmpty);
  });
}
