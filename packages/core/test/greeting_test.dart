import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The greeting must not outlive its hour.
///
/// These are the rules the header applies before it puts a phrase on screen:
/// which part of the day it is, which moment a cached phrase belongs to, and
/// whether a phrase can be spoken in that moment at all.
void main() {
  group('the parts of the day', () {
    test('are the four the local phrasings were written for', () {
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 4, 59)),
        NexGreetingPart.night,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 5)),
        NexGreetingPart.morning,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 11, 59)),
        NexGreetingPart.morning,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 12)),
        NexGreetingPart.afternoon,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 16, 59)),
        NexGreetingPart.afternoon,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 17)),
        NexGreetingPart.evening,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 22, 59)),
        NexGreetingPart.evening,
      );
      expect(
        nexGreetingPartOf(DateTime(2026, 3, 10, 23)),
        NexGreetingPart.night,
      );
    });

    test('round-trip through the form a cache stores', () {
      for (final part in NexGreetingPart.values) {
        expect(NexGreetingPart.fromWire(part.wireName), part);
      }
      expect(NexGreetingPart.fromWire(''), isNull);
      expect(NexGreetingPart.fromWire(null), isNull);
      // Old caches have no part at all, and that has to read as "not this
      // moment" rather than as midnight.
      expect(NexGreetingPart.fromWire('evening'), NexGreetingPart.evening);
    });
  });

  test('a moment is a day, a part and a language', () {
    final morning = nexGreetingMomentAt(
      DateTime(2026, 3, 10, 8),
      language: 'en',
    );
    expect(morning.dateKey, '2026-03-10');
    expect(morning.part, NexGreetingPart.morning);
    expect(morning.key, '2026-03-10|morning|en');
    expect(
      morning,
      nexGreetingMomentAt(DateTime(2026, 3, 10, 11, 59), language: 'en'),
    );
    expect(
      morning,
      isNot(nexGreetingMomentAt(DateTime(2026, 3, 10, 12), language: 'en')),
    );
    expect(
      morning,
      isNot(nexGreetingMomentAt(DateTime(2026, 3, 11, 8), language: 'en')),
    );
    expect(
      morning,
      isNot(nexGreetingMomentAt(DateTime(2026, 3, 10, 8), language: 'fa')),
    );
  });

  test('the next boundary is the next moment the line can change', () {
    final boundaries = nexGreetingBoundaries(DateTime(2026, 3, 10, 10));
    expect(boundaries, contains(DateTime(2026, 3, 10, 12)));
    final next = boundaries.firstWhere(
      (at) => at.isAfter(DateTime(2026, 3, 10, 10)),
    );
    expect(next, DateTime(2026, 3, 10, 12));
    // At 23:30 the next change is midnight, not another hour of tonight.
    final late = nexGreetingBoundaries(DateTime(2026, 3, 10, 23, 30));
    expect(
      late.firstWhere((at) => at.isAfter(DateTime(2026, 3, 10, 23, 30))),
      DateTime(2026, 3, 11),
    );
    // Just before a boundary the boundary itself is next.
    final early = nexGreetingBoundaries(DateTime(2026, 3, 10, 4, 59));
    expect(
      early.firstWhere((at) => at.isAfter(DateTime(2026, 3, 10, 4, 59))),
      DateTime(2026, 3, 10, 5),
    );
  });

  group('whether a phrase can be said now', () {
    NexGreetingMoment at(int hour) =>
        nexGreetingMomentAt(DateTime(2026, 3, 10, hour), language: 'en');

    test('a phrase that names the right part is welcome', () {
      expect(nexGreetingFits('Good morning', moment: at(8)), isTrue);
      expect(nexGreetingFits('Good afternoon', moment: at(14)), isTrue);
      expect(nexGreetingFits('Good evening', moment: at(19)), isTrue);
      expect(nexGreetingFits('Still up?', moment: at(1)), isTrue);
    });

    test('the night phrase from the bug report is not a morning phrase', () {
      // The line that stayed all night and greeted the morning.
      expect(nexGreetingFits('Still up?', moment: at(8)), isFalse);
      expect(nexGreetingFits('Good night', moment: at(9)), isFalse);
      expect(nexGreetingFits('Good morning', moment: at(1)), isFalse);
      expect(nexGreetingFits('Good morning', moment: at(23)), isFalse);
      expect(nexGreetingFits('Good evening', moment: at(8)), isFalse);
    });

    test('the Persian phrasings obey the same rule', () {
      final morning = nexGreetingMomentAt(
        DateTime(2026, 3, 10, 8),
        language: 'fa',
      );
      final night = nexGreetingMomentAt(
        DateTime(2026, 3, 10, 1),
        language: 'fa',
      );
      expect(nexGreetingFits('صبحت بخیر', moment: morning), isTrue);
      expect(nexGreetingFits('صبحت بخیر', moment: night), isFalse);
      expect(nexGreetingFits('هنوز بیداری؟', moment: night), isTrue);
      expect(nexGreetingFits('هنوز بیداری؟', moment: morning), isFalse);
      expect(nexGreetingFits('عصرت بخیر', moment: morning), isFalse);
      expect(
        nexGreetingFits('عصرت بخیر', moment: at(19)),
        isFalse,
        reason: 'an English moment cannot speak a Persian phrase',
      );
    });

    test('a phrase that names no part is welcome at any hour', () {
      for (final hour in [1, 8, 14, 19, 23]) {
        expect(
          nexGreetingFits('Ready when you are', moment: at(hour)),
          isTrue,
          reason: '$hour',
        );
      }
    });

    test('the shape has to be a phrase', () {
      expect(nexGreetingFits(null, moment: at(8)), isFalse);
      expect(nexGreetingFits('   ', moment: at(8)), isFalse);
      expect(nexGreetingFits('Good\nmorning', moment: at(8)), isFalse);
      // A paragraph is a summary, not a greeting — and the card would clip it.
      expect(nexGreetingFits('a b ' * 40, moment: at(8)), isFalse);
      expect(nexGreetingFits('x' * 91, moment: at(8)), isFalse);
    });

    test('the language of the moment has to be the language of the phrase', () {
      expect(nexGreetingFits('Ready when you are', moment: at(8)), isTrue);
      expect(
        nexGreetingFits(
          'Ready when you are',
          moment: nexGreetingMomentAt(DateTime(2026, 3, 10, 8), language: 'fa'),
        ),
        isFalse,
      );
      expect(
        nexGreetingFits(
          'صبحت بخیر',
          moment: nexGreetingMomentAt(DateTime(2026, 3, 10, 8), language: 'fa'),
        ),
        isTrue,
      );
    });
  });

  group('the headline source', () {
    test('a few notes are read deeply, under the budget', () {
      final long = 'a' * 500;
      final selected = nexHeadlineSource([long, '   ', 'a short thought']);
      // The empty entry is skipped and the indices name the notes the
      // prompt actually carried.
      expect(selected.map((e) => e.index), [0, 2]);
      expect(selected.first.line.length, greaterThan(200));
      expect(selected.first.line, endsWith('…'));
      expect(selected.last.line, 'a short thought');
    });

    test('many notes are read broadly, and the walk stops at the budget', () {
      final texts = [for (var i = 0; i < 100; i++) 'thought number $i'];
      final selected = nexHeadlineSource(texts);
      final used = selected.fold<int>(0, (sum, e) => sum + e.line.length + 1);
      expect(used, lessThanOrEqualTo(1600));
      expect(selected.length, lessThan(100));
      expect(selected.length, greaterThan(8));
      // Newest first, contiguous from the front.
      expect(selected.map((e) => e.index), [
        for (var i = 0; i < selected.length; i++) i,
      ]);
    });

    test('one long note cannot spend the whole budget twice over', () {
      final selected = nexHeadlineSource(['b' * 5000]);
      expect(selected.single.line.length, lessThanOrEqualTo(241));
    });

    test('nothing readable is nothing to greet from', () {
      expect(nexHeadlineSource(['', '   ', '\n']), isEmpty);
      expect(nexHeadlineSource(const []), isEmpty);
    });
  });
}
