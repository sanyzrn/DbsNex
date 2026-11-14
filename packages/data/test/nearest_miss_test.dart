import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// "The closest thing you actually wrote": what the empty result offers
/// when nothing matched. Scored word against word, so a long note with one
/// close word in it is still offered — the old whole-string score drowned it.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late LibraryMaintenance maintenance;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_miss_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
    maintenance = LibraryMaintenance(repo);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('a close word in a long note is offered', () {
    final filler = List.filled(40, 'بدون هیچ ارتباطی با موضوع').join(' ');
    final note = insert('قبض صورتحساب برق تیرماه $filler');

    final miss = maintenance.nearestMiss('صورتحسابها');

    // The old whole-string dice scored 2*8/(10+~460) ≈ 0.03 however close
    // the one matching word was, and the offer never appeared for a note
    // with more than a line or two in it.
    expect(miss?.id, note.id);
  });

  test('a typo in the first letter is still offered', () {
    final note = insert('طولانی‌مدت بودجه بندی سالانه');

    // No shared prefix for FTS, no substring: only the letter pairs say it.
    final miss = maintenance.nearestMiss('دولانی');

    expect(miss?.id, note.id);
  });

  test('an unrelated query offers nothing', () {
    insert('خرید نان و پنیر');
    expect(maintenance.nearestMiss('ماهواره'), isNull);
  });

  test('Persian spellings fold before comparing', () {
    final note = insert('مسئلهٔ فیزیک کوانتومی');
    // Typed with Arabic kaf and without the final heh: still the same word
    // once folded.
    final miss = maintenance.nearestMiss('کوانتومي');
    expect(miss?.id, note.id);
  });

  test('an empty or mark-only query offers nothing', () {
    insert('something to say');
    expect(maintenance.nearestMiss(''), isNull);
    expect(maintenance.nearestMiss('‌'), isNull);
    expect(maintenance.nearestMiss('"'), isNull);
  });

  test('a voice note with a transcript is a candidate', () {
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.voice,
        mediaUri: '/tmp/a.m4a',
        mediaHash: 'h',
        durationMs: 1000,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    repo.setTranscriptText(note.id, 'جلسهٔ هیئت‌مدیره هفتهٔ آینده');
    // No `content` at all: the transcript is the words, and the closest
    // thing has always been allowed to be a voice note reading of them.
    expect(maintenance.nearestMiss('مدیران')?.id, note.id);
  });

  test('a note that shares more of the query wins', () {
    final one = insert('تعمیر پکیج');
    insert('تعمیرات بسته');

    final miss = maintenance.nearestMiss('تعمیر پکیج');

    expect(miss?.id, one.id);
  });
}
