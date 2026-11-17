import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// The propagation contract: a write that changes the library's shape tells
/// the timeline stream, whatever screen happened to be standing in front of
/// it.
///
/// Every listener downstream of the home screen — the cards, the filter row,
/// the shelves, the home-screen widget — reads the library through
/// [NexServices.timelineStream]. The tag paths used to be the one family of
/// writes that never fired it, and every one of those surfaces showed the
/// previous state until an unrelated capture happened along: a tag renamed
/// in the manager, a suggestion accepted in the assistant panel, a checklist
/// line ticked in the detail sheet. The service layer owns the propagation
/// now; these tests pin it there, where forgetting it used to live.
void main() {
  late Directory tmp;
  late NexServices services;
  late StreamSubscription<List<Note>> subscription;
  var deliveries = 0;

  Future<void> buildServices() async {
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
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_propagation_');
    await buildServices();
    deliveries = 0;
    subscription = services.timelineStream.listen((_) => deliveries++);
  });

  tearDown(() async {
    await subscription.cancel();
    await services.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// A broadcast stream delivers asynchronously: the write has finished when
  /// its await returns, and the listeners hear of it a turn later. Flushing
  /// the queue before reading the counter is the difference between testing
  /// the write and testing the clock.
  Future<void> delivered() => pumpEventQueue();

  test('tagging a note tells the timeline', () async {
    final note = await services.captureText('a note to file');
    final before = deliveries;
    await services.addTag(noteId: note!.id, name: 'Work');
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test('removing a tag tells the timeline', () async {
    final note = await services.captureText('a note to unfile');
    final tag = await services.addTag(noteId: note!.id, name: 'Work');
    final before = deliveries;
    await services.removeTag(noteId: note.id, tagId: tag.id);
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test('creating a tag nobody wears yet still tells the timeline', () async {
    final before = deliveries;
    await services.createTag('Someday');
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test(
    'renaming, recolouring, merging and deleting tags tell the timeline',
    () async {
      final note = await services.captureText('a tagged note');
      final keep = await services.createTag('Keep');
      final gone = await services.createTag('Gone');
      await services.addTag(noteId: note!.id, name: 'Keep');
      await services.addTag(noteId: note.id, name: 'Gone');

      var before = deliveries;
      await services.renameTag(keep.id, 'Kept');
      await delivered();
      expect(deliveries, greaterThan(before));

      before = deliveries;
      await services.setTagColor(tagId: keep.id, color: '#2FBF8F');
      await delivered();
      expect(deliveries, greaterThan(before));

      before = deliveries;
      await services.mergeTag(sourceId: gone.id, targetId: keep.id);
      await delivered();
      expect(deliveries, greaterThan(before));

      before = deliveries;
      await services.deleteTag(keep.id);
      await delivered();
      expect(deliveries, greaterThan(before));
    },
  );

  test('ticking a checklist line tells the timeline', () async {
    final note = await services.captureChecklist(const [
      ChecklistItem(text: 'one', done: false),
      ChecklistItem(text: 'two', done: false),
    ]);
    final before = deliveries;
    await services.toggleChecklistItem(note!.id, 0);
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test('naming and pinning a note tell the timeline', () async {
    final note = await services.captureText('a nameless note');
    var before = deliveries;
    await services.setTitle(note!.id, 'The name');
    await delivered();
    expect(deliveries, greaterThan(before));

    before = deliveries;
    await services.pinNote(note.id);
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test('putting a note aside and bringing it back tell the timeline', () async {
    final note = await services.captureText('an aside note');
    var before = deliveries;
    await services.setAside(note!.id);
    await delivered();
    expect(deliveries, greaterThan(before));

    before = deliveries;
    await services.bringBack(note.id);
    await delivered();
    expect(deliveries, greaterThan(before));
  });

  test(
    'a held note stays waiting, and its arrival tells the timeline',
    () async {
      final note = await services.captureText('a note for later');
      final later = DateTime.now().toUtc().add(const Duration(days: 1));
      final held = await services.scheduleNote(note!.id, later);
      expect(held, isNotNull);
      expect(
        (await services.timeline()).map((n) => n.id),
        isEmpty,
        reason: 'hidden from the home until its time',
      );

      final arrived = await services.releaseScheduledNow(note.id);
      expect(arrived, isNotNull);
      expect(arrived!.content, 'a note for later');
      expect(
        (await services.timeline()).single.id,
        note.id,
        reason: 'delivered, back on the timeline',
      );
    },
  );

  test('a refused schedule leaves the note exactly as it was', () async {
    final note = await services.captureText('has a file attached');
    final attached = File(p.join(tmp.path, 'attached.bin'))
      ..writeAsBytesSync([1, 2, 3]);
    await services.attachFile(
      note!.id,
      attached.path,
      kind: AttachmentKind.file,
    );
    final before = (await services.getById(note.id))!;

    final held = await services.scheduleNote(
      note.id,
      DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    expect(held, isNull, reason: 'attachments refuse the wait');

    // The refusal is a no-op on the note: still live, still on the timeline,
    // unchanged — not a note whose supporting facts were torn down first.
    final after = await services.getById(note.id);
    expect(after, isNotNull);
    expect(after!.content, before.content);
    expect((await services.timeline()).map((n) => n.id), [note.id]);
  });
}
