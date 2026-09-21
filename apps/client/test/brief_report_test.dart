import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/brief_report.dart';

/// The brief nobody is asked for.
///
/// Every line here is a fact already in the database, put into the reader's
/// language and nothing else — no provider, no key, no request. That is the
/// whole claim of the plain-report style, and it is also what the two styles
/// with a model in them state before the model is asked for anything, so a
/// mistake in here is a mistake in three of the five.
void main() {
  late AppLocalizations en;
  final now = DateTime(2026, 3, 10, 9);

  setUp(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Note note({
    required String id,
    required String text,
    DateTime? dueAt,
    NoteType type = NoteType.text,
  }) => Note(
    id: id,
    type: type,
    content: text,
    createdAt: now,
    updatedAt: now,
    dueAt: dueAt,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  test('a quiet day is not filled in', () {
    final report = nexBriefReport(
      nexBriefFacts([note(id: '1', text: 'a thought')], now: now),
      en,
      now: now,
    );
    // Null rather than "you have 1 note". The card has a line for a day with
    // nothing on it, and manufacturing a sentence to cover the silence is the
    // habit this whole setting exists to break.
    expect(report, isNull);
  });

  test('what is waiting is said, in the order it matters', () {
    final report = nexBriefReport(
      nexBriefFacts(
        [
          note(
            id: '1',
            text: 'call the plumber',
            dueAt: now.subtract(const Duration(days: 2)),
          ),
          note(
            id: '2',
            text: 'dentist',
            dueAt: now.add(const Duration(days: 1)),
          ),
          note(
            id: '3',
            text: '- [ ] milk\n- [x] bread',
            type: NoteType.checklist,
          ),
        ],
        now: now,
      ),
      en,
      now: now,
    );
    final lines = report!.split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], contains('call the plumber'));
    expect(lines[0], contains('overdue'));
    expect(lines[1], contains('dentist'));
    expect(lines[2], contains('1 of 2 left'));
  });

  test('the budget is spent from the top', () {
    final report = nexBriefReport(
      nexBriefFacts(
        [
          for (var i = 0; i < 5; i++)
            note(
              id: 'overdue-$i',
              text: 'bill $i',
              dueAt: now.subtract(Duration(days: 5 - i)),
            ),
          note(
            id: 'list',
            text: '- [ ] milk',
            type: NoteType.checklist,
          ),
        ],
        now: now,
      ),
      en,
      now: now,
      maxLines: 2,
    );
    // Two overdue bills rather than one bill and a shopping list. A brief
    // that drops the third unpaid thing to make room for an unticked item has
    // its priorities the wrong way round.
    final lines = report!.split('\n');
    expect(lines, hasLength(2));
    expect(lines.every((line) => line.contains('bill')), isTrue);
  });

  test('a standing commitment is said like the notes beside it', () {
    final report = nexBriefReport(
      nexBriefFacts(
        const [],
        commitments: [
          NexCommitment(
            id: 'c1',
            title: 'rent',
            cadence: NexCadence.months,
            every: 1,
            dueAt: now.subtract(const Duration(days: 3)),
            createdAt: now,
            updatedAt: now,
          ),
        ],
        now: now,
      ),
      en,
      now: now,
    );
    expect(report, contains('rent'));
    expect(report, contains('3 days overdue'));
  });

  group('what a brief was made from', () {
    // The bug this group is for: the recap is cached against a fingerprint of
    // what it was written from, and that fingerprint was the notes alone. So
    // changing the style, the tone, the length or the language left the old
    // brief on the card until somebody happened to write a note — every one
    // of those settings appeared to do nothing.
    //
    // The headline beside the brief has always keyed its own cache on the
    // language, which is exactly how an English greeting ended up sitting
    // over a Persian brief on the same screen.
    String signature({
      String source = 'today | text | a note',
      NexBriefStyle style = NexBriefStyle.assistant,
      AiResponseStyle tone = AiResponseStyle.natural,
      NexBriefLength length = NexBriefLength.medium,
      AiOutputLanguage language = AiOutputLanguage.auto,
      String instruction = '',
    }) => nexBriefSignature(
      source: source,
      style: style,
      tone: tone,
      length: length,
      language: language,
      instruction: instruction,
    );

    test('the same settings over the same notes ask nothing new', () {
      expect(signature(), signature());
    });

    test('every setting that shapes it is part of it', () {
      final base = signature();
      expect(signature(style: NexBriefStyle.planner), isNot(base));
      expect(signature(tone: AiResponseStyle.formal), isNot(base));
      expect(signature(length: NexBriefLength.short), isNot(base));
      expect(signature(language: AiOutputLanguage.english), isNot(base));
      expect(signature(instruction: 'only what is overdue'), isNot(base));
      expect(signature(source: 'today | text | another note'), isNot(base));
    });

    test('whitespace around a custom instruction is not a change', () {
      // Otherwise a trailing space typed into the field would spend a
      // provider call on a brief identical to the one already showing.
      expect(
        signature(instruction: '  only what is overdue  '),
        signature(instruction: 'only what is overdue'),
      );
    });
  });
}
