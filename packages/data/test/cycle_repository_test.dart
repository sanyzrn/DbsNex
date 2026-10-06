import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteCycleRepository cycle;
  late SqliteNoteRepository notes;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_cycle_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    cycle = SqliteCycleRepository(db);
    notes = SqliteNoteRepository(db, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('start, end, edit and delete a period', () {
    final p1 = cycle.startPeriod(DateTime(2026, 9, 3));
    expect(p1.isOpen, isTrue);
    cycle.endPeriod(p1.id, DateTime(2026, 9, 7));
    expect(cycle.periods().single.length, 5);

    // An end before the start is clamped, not stored backwards.
    cycle.endPeriod(p1.id, DateTime(2026, 9, 1));
    expect(cycle.periods().single.end, const CycleDate(2026, 9, 3));

    cycle.updatePeriod(p1.id, DateTime(2026, 9, 2), DateTime(2026, 9, 6));
    expect(cycle.periods().single.start, const CycleDate(2026, 9, 2));
    cycle.deletePeriod(p1.id);
    expect(cycle.periods(), isEmpty);
  });

  test('"started" twice, or a day late, is still one period', () {
    final first = cycle.startPeriod(DateTime(2026, 10, 1));
    expect(cycle.startPeriod(DateTime(2026, 10, 1)).id, first.id);
    expect(cycle.startPeriod(DateTime(2026, 10, 3)).id, first.id);
    expect(cycle.periods(), hasLength(1));
  });

  test('a forgotten open period is closed when the next one starts', () {
    cycle.startPeriod(DateTime(2026, 9, 1));
    cycle.startPeriod(DateTime(2026, 9, 29), closeAfter: 6);
    final all = cycle.periods();
    expect(all, hasLength(2));
    expect(all.first.end, const CycleDate(2026, 9, 6));
    expect(all.last.isOpen, isTrue);
  });

  test('a day keeps everything noted, and an empty day is forgotten', () {
    final day = CycleDayLog(
      day: const CycleDate(2026, 10, 2),
      flow: CycleFlow.heavy,
      symptoms: {CycleSymptom.cramps, CycleSymptom.headache},
      mood: CycleMood.sensitive,
      energy: 2,
      painRelief: true,
      note: '  hot water bottle  ',
    );
    cycle.saveDay(day);
    final back = cycle.day(DateTime(2026, 10, 2))!;
    expect(back.flow, CycleFlow.heavy);
    expect(back.symptoms, {CycleSymptom.cramps, CycleSymptom.headache});
    expect(back.mood, CycleMood.sensitive);
    expect(back.energy, 2);
    expect(back.painRelief, isTrue);
    expect(back.intimacy, isFalse);
    expect(back.note, 'hot water bottle');
    expect(
      cycle.days(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      hasLength(1),
    );

    cycle.saveDay(CycleDayLog(day: const CycleDate(2026, 10, 2)));
    expect(cycle.day(DateTime(2026, 10, 2)), isNull);
  });

  test('delete all removes the cycle and nothing else', () {
    final note = CaptureService(
      notes,
      deviceId: 'd',
    ).submitTextCapture('a note')!;
    cycle.startPeriod(DateTime(2026, 10, 1));
    cycle.saveDay(
      CycleDayLog(day: const CycleDate(2026, 10, 1), flow: CycleFlow.light),
    );
    cycle.deleteAll();
    expect(cycle.periods(), isEmpty);
    expect(cycle.days(DateTime(2000), DateTime(2100)), isEmpty);
    expect(notes.getById(note.id), isNotNull);
  });

  test('cycle data never reaches notes or search', () {
    cycle.saveDay(
      CycleDayLog(
        day: const CycleDate(2026, 10, 1),
        note: 'private words about cramps',
      ),
    );
    expect(notes.listTimeline(), isEmpty);
    expect(notes.search(const SearchFilters(query: 'cramps')), isEmpty);
  });
}
