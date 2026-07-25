import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

NoteRevision rev({
  required String id,
  String? content,
  required DateTime updatedAt,
  int rev = 1,
  Set<String> tags = const {},
  DateTime? deletedAt,
  String? mediaUri,
  String? mediaHash,
  String deviceId = 'dev',
}) {
  return NoteRevision(
    id: id,
    type: NoteType.text,
    content: content,
    mediaUri: mediaUri,
    mediaHash: mediaHash,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    deviceId: deviceId,
    rev: rev,
    tagIds: tags,
  );
}

void main() {
  const merger = FieldAwareMerger();

  group('ADR-020 field-aware merge', () {
    test('concurrent content edit: later updated_at wins (LWW scalar)', () {
      final a = rev(
        id: 'n1',
        content: 'from A',
        updatedAt: DateTime.utc(2026, 1, 1, 10),
        rev: 2,
      );
      final b = rev(
        id: 'n1',
        content: 'from B',
        updatedAt: DateTime.utc(2026, 1, 1, 11),
        rev: 2,
      );
      final m = merger.merge(a, b);
      expect(m.content, 'from B');
      expect(m.tagIds, isEmpty);
    });

    test('tag add on A + tag remove on B: concurrent union keeps both sides', () {
      // Start conceptually with {x,y}. A adds nothing extra but still has both;
      // B removes x → {y}. Concurrent devices → union keeps x and y.
      // (ADR-020: never silently drop a tag that lost a whole-record race.)
      final a = rev(
        id: 'n1',
        content: 'body',
        updatedAt: DateTime.utc(2026, 1, 1, 10),
        tags: {'tag-x', 'tag-y'},
        deviceId: 'device-a',
      );
      final b = rev(
        id: 'n1',
        content: 'body',
        updatedAt: DateTime.utc(2026, 1, 1, 11),
        tags: {'tag-y'},
        deviceId: 'device-b',
      );
      final m = merger.merge(a, b);
      expect(m.tagIds, containsAll(['tag-x', 'tag-y']));
    });

    test('same-device sequential tag remove: later set wins', () {
      final a = rev(
        id: 'n1',
        content: 'body',
        updatedAt: DateTime.utc(2026, 1, 1, 10),
        tags: {'tag-x', 'tag-y'},
        deviceId: 'phone',
      );
      final b = rev(
        id: 'n1',
        content: 'body',
        updatedAt: DateTime.utc(2026, 1, 1, 11),
        tags: {'tag-y'},
        deviceId: 'phone',
      );
      final m = merger.merge(a, b);
      expect(m.tagIds, equals({'tag-y'}));
    });

    test('tag add on A + content edit on B: BOTH survive (union-merge)', () {
      final a = rev(
        id: 'n1',
        content: 'original',
        updatedAt: DateTime.utc(2026, 1, 1, 10),
        tags: {'tag-work'},
        rev: 2,
        deviceId: 'device-a',
      );
      final b = rev(
        id: 'n1',
        content: 'edited on B',
        updatedAt: DateTime.utc(2026, 1, 1, 11),
        tags: {},
        rev: 2,
        deviceId: 'device-b',
      );
      final m = merger.merge(a, b);
      expect(m.content, 'edited on B');
      expect(m.tagIds, contains('tag-work'),
          reason: 'tag must not be lost to whole-record LWW');
    });

    test('delete vs edit: deletion (tombstone) wins', () {
      final a = rev(
        id: 'n1',
        content: 'still editing',
        updatedAt: DateTime.utc(2026, 1, 1, 12),
        rev: 3,
      );
      final b = rev(
        id: 'n1',
        content: 'gone',
        updatedAt: DateTime.utc(2026, 1, 1, 11),
        deletedAt: DateTime.utc(2026, 1, 1, 11),
        rev: 2,
      );
      final m = merger.merge(a, b);
      expect(m.deletedAt, isNotNull);
    });

    test('identical media_hash is duplicate', () {
      expect(
        FieldAwareMerger.isDuplicateMedia('abc', 'abc'),
        isTrue,
      );
      expect(
        FieldAwareMerger.isDuplicateMedia('abc', 'xyz'),
        isFalse,
      );
    });
  });
}
