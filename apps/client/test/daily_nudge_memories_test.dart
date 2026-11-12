import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/daily_nudge_content.dart';
import 'package:nex_core/nex_core.dart';

Note _note(
  String id,
  DateTime created, {
  String? body,
  NoteType type = NoteType.text,
  String? caption,
  DateTime? deleted,
  DateTime? setAside,
  bool urgent = false,
}) => Note(
  id: id,
  type: type,
  content: type == NoteType.text ? body ?? id : null,
  caption: caption,
  isUrgent: urgent,
  createdAt: created,
  updatedAt: created,
  deletedAt: deleted,
  setAsideAt: setAside,
  deviceId: 'test',
  rev: 1,
  syncState: SyncState.pending,
);

/// "On this day" (2.6.23): a quiet day's nudge quotes a note from the same
/// date in an earlier year, instead of a line anyone could be sent.
void main() {
  final at = DateTime(2026, 11, 3, 9);

  List<String> local(
    List<Note> memories, {
    List<Note> notes = const [],
    bool persian = false,
    bool solarCalendar = false,
    DateTime? when,
  }) => NexDailyNudgeContent.local(
    NexNudgeSnapshot(
      notes: notes,
      commitments: const [],
      hasData: true,
      memories: memories,
    ),
    when ?? at,
    persian: persian,
    solarCalendar: solarCalendar,
  );

  test('a quiet day quotes the note written a year ago today', () {
    final bodies = local([
      _note('a', DateTime(2025, 11, 3, 22), body: 'Planted the fig tree'),
    ]);
    expect(bodies, ['A year ago today you wrote: “Planted the fig tree”']);
  });

  test('in Persian, with Persian digits for the years', () {
    expect(
      local([
        _note('a', DateTime(2025, 11, 3, 7), body: 'درخت انجیر را کاشتم'),
      ], persian: true),
      ['پارسال، همین روز نوشتی: «درخت انجیر را کاشتم»'],
    );
    expect(
      local([
        _note('a', DateTime(2023, 11, 3, 7), body: 'درخت انجیر را کاشتم'),
      ], persian: true),
      ['۳ سال پیش، همین روز نوشتی: «درخت انجیر را کاشتم»'],
    );
  });

  test('the nearest year wins', () {
    final bodies = local([
      _note('old', DateTime(2022, 11, 3, 10), body: 'four years back'),
      _note('near', DateTime(2025, 11, 3, 10), body: 'last year'),
      _note('mid', DateTime(2024, 11, 3, 10), body: 'two years back'),
    ]);
    expect(bodies.single, contains('last year'));
    expect(bodies.single, startsWith('A year ago today'));
  });

  test('another date, this year and a wordless note are not memories', () {
    final quiet = NexDailyNudgeContent.quietEn;
    expect(local([_note('a', DateTime(2025, 11, 4, 10))]), quiet);
    expect(local([_note('a', DateTime(2025, 11, 2, 10))]), quiet);
    expect(local([_note('a', DateTime(2026, 11, 3, 1))]), quiet);
    expect(
      local([_note('a', DateTime(2025, 11, 3, 10), type: NoteType.photo)]),
      quiet,
    );
    expect(local([_note('a', DateTime(2025, 11, 3, 10), body: '   ')]), quiet);
  });

  test('a photo is remembered by its caption', () {
    expect(
      local([
        _note(
          'a',
          DateTime(2024, 11, 3, 10),
          type: NoteType.photo,
          caption: 'First snow',
        ),
      ]),
      ['2 years ago today you wrote: “First snow”'],
    );
  });

  test('a deleted or set-aside note is never brought back', () {
    final quiet = NexDailyNudgeContent.quietEn;
    expect(
      local([
        _note('a', DateTime(2025, 11, 3, 10), deleted: DateTime(2026, 1, 1)),
      ]),
      quiet,
    );
    expect(
      local([
        _note('a', DateTime(2025, 11, 3, 10), setAside: DateTime(2026, 1, 1)),
      ]),
      quiet,
    );
  });

  test('anything due or urgent comes first; a memory only fills quiet', () {
    final bodies = local(
      [_note('a', DateTime(2025, 11, 3, 10), body: 'old thought')],
      notes: [
        _note('u', DateTime(2026, 11, 1), body: 'call the bank', urgent: true),
      ],
    );
    expect(bodies.first, contains('call the bank'));
    expect(bodies.join(), isNot(contains('old thought')));
  });

  test('a long note is quoted in part and the line stays short', () {
    final bodies = local([
      _note('a', DateTime(2025, 11, 3, 10), body: 'word ' * 200),
    ]);
    expect(bodies.single.runes.length, lessThanOrEqualTo(210));
    expect(bodies.single, endsWith('…”'));
  });

  test('with the Persian calendar the anniversary is the Persian date', () {
    // 12 Aban 1404 was 3 November 2025; 12 Aban 1403 was 2 November 2024,
    // because 2024 held a leap day the Persian year did not.
    final aban12 = _note('a', DateTime(2024, 11, 2, 10), body: 'دوازده آبان');
    expect(nexPersianDate(DateTime(2025, 11, 3)), (
      year: 1404,
      month: 8,
      day: 12,
    ));
    expect(nexPersianDate(DateTime(2024, 11, 2)), (
      year: 1403,
      month: 8,
      day: 12,
    ));
    final day = DateTime(2025, 11, 3, 9);
    expect(local([aban12], persian: true, solarCalendar: true, when: day), [
      'پارسال، همین روز نوشتی: «دوازده آبان»',
    ]);
    // The Gregorian reader's 3 November is a different day of that year.
    expect(
      local([aban12], persian: true, when: day),
      NexDailyNudgeContent.quietFa,
    );
  });

  test('the plan carries a memory on its own day and not on the others', () {
    final plan = NexDailyNudgeContent.plan(
      source: NexNudgeSnapshot(
        notes: const [],
        commitments: const [],
        hasData: true,
        memories: [_note('a', DateTime(2025, 11, 5, 10), body: 'two days on')],
      ),
      now: DateTime(2026, 11, 3, 8),
      minutes: 9 * 60,
      persian: false,
      title: 'Nex',
      aiEnabled: false,
      summaryEnabled: false,
      sourceMatches: false,
      summary: null,
      summaryAt: null,
      secret: false,
    );
    final days = plan['days']! as Map<String, Object?>;
    expect((days['2026-11-05']! as Map)['localBodies'], [
      'A year ago today you wrote: “two days on”',
    ]);
    expect(
      (days['2026-11-03']! as Map)['localBodies'],
      NexDailyNudgeContent.quietEn,
    );
    expect(
      (days['2026-11-06']! as Map)['localBodies'],
      NexDailyNudgeContent.quietEn,
    );
  });
}
