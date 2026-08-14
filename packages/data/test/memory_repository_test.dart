import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  late NexDatabase db;
  late SqliteMemoryRepository repo;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteMemoryRepository(db);
  });

  tearDown(() => db.close());

  MemoryRecord makeRecord({
    MemoryKind kind = MemoryKind.preference,
    String valueText = 'prefers Persian replies',
  }) {
    final now = DateTime.now().toUtc();
    return MemoryRecord(
      id: newUuidV7(),
      kind: kind,
      valueText: valueText,
      source: MemorySource.userDirect,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test-device',
      rev: 1,
    );
  }

  group('SqliteMemoryRepository', () {
    test('insert then getById round-trips every field', () {
      final record = repo.insert(makeRecord());
      final fetched = repo.getById(record.id);
      expect(fetched, isNotNull);
      expect(fetched!.kind, MemoryKind.preference);
      expect(fetched.valueText, 'prefers Persian replies');
      expect(fetched.source, MemorySource.userDirect);
      expect(fetched.deviceId, 'test-device');
      expect(fetched.rev, 1);
    });

    test('listByKind returns only matching, non-deleted records', () {
      repo.insert(makeRecord(kind: MemoryKind.preference));
      repo.insert(
        makeRecord(kind: MemoryKind.habit, valueText: 'writes at night'),
      );
      final preferences = repo.listByKind(MemoryKind.preference);
      expect(preferences, hasLength(1));
      expect(preferences.single.kind, MemoryKind.preference);
    });

    test('softDelete hides a record from getById and listByKind', () {
      final record = repo.insert(makeRecord());
      repo.softDelete(record.id);
      expect(repo.getById(record.id), isNull);
      expect(repo.listByKind(record.kind), isEmpty);
      expect(
        repo.getById(record.id, includeDeleted: true)?.deletedAt,
        isNotNull,
      );
    });

    test('update bumps rev and changes valueText', () {
      final record = repo.insert(makeRecord());
      final updated = repo.update(
        MemoryRecord(
          id: record.id,
          kind: record.kind,
          valueText: 'prefers English replies',
          source: record.source,
          createdAt: record.createdAt,
          updatedAt: record.updatedAt,
          deviceId: record.deviceId,
          rev: record.rev,
        ),
      );
      expect(updated.valueText, 'prefers English replies');
      expect(updated.rev, 2);
    });
  });
}
