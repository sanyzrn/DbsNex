import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// 2.1.7: the writing portrait in the profile.
void main() {
  final now = DateTime.utc(2026, 10, 18, 12);

  Note note(
    String id, {
    required DateTime at,
    NoteType type = NoteType.text,
    String content = 'a thought',
    List<String> tags = const [],
    DateTime? deletedAt,
  }) => Note(
    id: id,
    type: type,
    content: content,
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    tags: [for (final name in tags) Tag(id: name, name: name, createdAt: at)],
  );

  group('nexWritingStats', () {
    test('counts the rhythm, the kinds, the tags and the days', () {
      final notes = [
        for (var i = 0; i < 20; i++)
          note('e$i', at: DateTime.utc(2026, 10, 1 + i, 19), tags: ['work']),
        for (var i = 0; i < 6; i++)
          note('m$i', at: DateTime.utc(2026, 10, 1 + i, 8), tags: ['trip']),
        note(
          'list',
          at: DateTime.utc(2026, 10, 10, 13),
          type: NoteType.checklist,
          content: '- [x] milk\n- [ ] bread\n- [x] tea',
        ),
        note('gone', at: now, deletedAt: now),
      ];
      final stats = nexWritingStats(notes, now: now);
      expect(stats.notes, 27);
      expect(stats.days, 20);
      expect(stats.activeLast30, 20);
      expect(stats.dayParts, [6, 1, 20, 0]);
      expect(stats.peak, NexDayPart.evening);
      expect(stats.types.first, (NoteType.text, 26));
      expect(stats.tags, [('work', 20), ('trip', 6)]);
      expect(stats.checklistRate, closeTo(2 / 3, 1e-9));
      // Three short of the notes needed, and enough days.
      expect(stats.unlocked, isFalse);
      expect(stats.notesToGo, 3);
      expect(stats.daysToGo, 0);
    });

    test('a library written in one afternoon is not a portrait yet', () {
      final stats = nexWritingStats([
        for (var i = 0; i < 40; i++)
          note('n$i', at: DateTime.utc(2026, 10, 17, 14, i)),
      ], now: now);
      expect(stats.notes, 40);
      expect(stats.unlocked, isFalse);
      expect(stats.daysToGo, NexWritingStats.minDays - 1);
    });
  });

  group('nexPortraitSource', () {
    test('spreads across the library and cuts long notes', () {
      final notes = [
        for (var i = 0; i < 200; i++)
          note(
            'n$i',
            at: now.subtract(Duration(days: i)),
            content: i == 0 ? 'x' * 500 : 'note $i',
            tags: i.isEven ? ['even'] : const [],
          ),
        note('photo', at: now, type: NoteType.photo, content: ''),
      ];
      final source = nexPortraitSource(notes, limit: 50, now: now);
      final lines = source.text.split('\n');
      expect(lines, hasLength(50));
      expect(source.ids, hasLength(50));
      expect(source.ids, isNot(contains('photo')));
      // Newest to oldest, across the whole span rather than the last 50.
      expect(source.ids.first, 'n0');
      expect(source.ids.last, 'n196');
      expect(lines.first, startsWith('today | text #even | '));
      expect(lines.first.length, lessThan(240));
      expect(lines.first, endsWith('…'));
      expect(lines.last, startsWith('6 months ago | text #even | '));
    });
  });

  group('NexPortrait', () {
    const reply =
        'Here you go:\n```json\n{"headline": "A careful planner", '
        '"portrait": "You write things down before they slip.", '
        '"traits": [{"name": "Planning", "score": 88, "line": "Lists."}, '
        '{"name": "Curiosity", "score": 140, "line": "Links."}, '
        '{"name": "Care", "score": "high", "line": "Reminders."}], '
        '"strengths": ["follow-through", "", "noticing"], '
        '"invitation": "Close one list a week."}\n```';

    test('reads a reply leniently and checks it strictly', () {
      final portrait = NexPortrait.parse(reply, writtenAt: now, basedOn: 80)!;
      expect(portrait.headline, 'A careful planner');
      expect(portrait.traits.map((t) => t.score), [88, 100, 50]);
      expect(portrait.strengths, ['follow-through', 'noticing']);
      expect(portrait.basedOn, 80);
      final kept = NexPortrait.decode(portrait.encode())!;
      expect(kept.headline, portrait.headline);
      expect(kept.traits.length, 3);
      expect(kept.writtenAt, now);
    });

    test('half a portrait is none', () {
      expect(
        NexPortrait.parse(
          '{"headline": "x", "portrait": "", "traits": []}',
          writtenAt: now,
          basedOn: 1,
        ),
        isNull,
      );
      expect(NexPortrait.parse('no json', writtenAt: now, basedOn: 1), isNull);
      expect(NexPortrait.decode('{broken'), isNull);
    });
  });
}
