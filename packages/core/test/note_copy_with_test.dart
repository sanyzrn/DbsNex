import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// A copy of a note is still that note.
///
/// `copyWith` forwarded fifteen fields and quietly dropped four: [Note.pinnedAt],
/// [Note.dueAt], [Note.dueRepeat] and [Note.sortOrder]. They are not incidental
/// — the first and last are what the timeline orders by, and the middle two are
/// the whole of what the reminder scheduler reads — so a copy reverted a pinned
/// note to unpinned and a note with an alarm to one without, with no error and
/// nothing in the diff to point at.
///
/// Nothing reached it: every write in the repository goes through a dedicated
/// method and `insert(Note)` is the only Note-taking write. This is here so it
/// stays that way, because the shape of that failure is the expensive one. It
/// would have arrived days later as "the reminder disappeared".
void main() {
  Note note({
    DateTime? pinnedAt,
    DateTime? dueAt,
    NoteRepeat dueRepeat = NoteRepeat.once,
    int? sortOrder,
  }) => Note(
    id: 'n1',
    type: NoteType.text,
    content: 'something worth keeping',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    pinnedAt: pinnedAt,
    dueAt: dueAt,
    dueRepeat: dueRepeat,
    sortOrder: sortOrder,
  );

  test('an unrelated edit keeps the pin, the alarm and the order', () {
    final original = note(
      pinnedAt: DateTime.utc(2026, 5, 10),
      dueAt: DateTime.utc(2026, 6, 1, 9),
      dueRepeat: NoteRepeat.weekly,
      sortOrder: 7,
    );

    final edited = original.copyWith(content: 'edited');

    expect(edited.content, 'edited');
    expect(edited.pinnedAt, original.pinnedAt);
    expect(edited.dueAt, original.dueAt);
    expect(edited.dueRepeat, NoteRepeat.weekly);
    expect(edited.sortOrder, 7);
  });

  test('each of the four can be set', () {
    final changed = note().copyWith(
      pinnedAt: DateTime.utc(2027),
      dueAt: DateTime.utc(2027, 2, 3),
      dueRepeat: NoteRepeat.daily,
      sortOrder: 3,
    );
    expect(changed.pinnedAt, DateTime.utc(2027));
    expect(changed.dueAt, DateTime.utc(2027, 2, 3));
    expect(changed.dueRepeat, NoteRepeat.daily);
    expect(changed.sortOrder, 3);
  });

  test('and each of the nullable three can be cleared, explicitly', () {
    // The distinction `?? this.x` cannot express on its own: passing null
    // means "leave it", so unpinning needs a flag of its own. The same shape
    // `clearCaption`, `clearTitle` and `clearDeletedAt` already use.
    final original = note(
      pinnedAt: DateTime.utc(2026, 5, 10),
      dueAt: DateTime.utc(2026, 6, 1),
      sortOrder: 7,
    );
    final cleared = original.copyWith(
      clearPinnedAt: true,
      clearDueAt: true,
      clearSortOrder: true,
    );
    expect(cleared.pinnedAt, isNull);
    expect(cleared.dueAt, isNull);
    expect(cleared.sortOrder, isNull);
    // Passing nothing is not clearing.
    expect(original.copyWith().pinnedAt, isNotNull);
    expect(original.copyWith().dueAt, isNotNull);
    expect(original.copyWith().sortOrder, 7);
  });
}
