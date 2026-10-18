import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  Note note(String body, {NoteType type = NoteType.text, int? duration}) =>
      Note(
        id: 'card',
        type: type,
        content: body,
        durationMs: duration,
        transcriptText: type == NoteType.voice ? body : null,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
  for (final density in NexCardDensity.values) {
    for (final scale in [1.0, 3.2]) {
      testWidgets(
        'expansion measures content at ${density.name}, scale $scale',
        (tester) async {
          late BuildContext cardContext;
          await tester.pumpWidget(
            MaterialApp(
              theme: nexLightTheme(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: NexCardDensityScope(
                  density: density,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) {
                        cardContext = context;
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          bool expands(Note value) =>
              nexNoteCanExpand(cardContext, value, cardWidth: 360);
          expect(expands(note('Hi')), isFalse);
          expect(expands(note('**Hi**')), isFalse);
          expect(
            expands(note(List.filled(100, 'متن فارسی English text').join(' '))),
            isTrue,
          );
          expect(expands(note('', type: NoteType.photo)), isFalse);
          expect(
            expands(
              note(
                'https://example.com/a-very-long-title',
                type: NoteType.link,
              ),
            ),
            isFalse,
          );
          expect(
            expands(note('- [ ] milk\n- [x] bread', type: NoteType.checklist)),
            isFalse,
          );
          expect(
            expands(
              note(
                '- [ ] milk\n- [x] bread\n- [ ] tea\n- [ ] cake',
                type: NoteType.checklist,
              ),
            ),
            isTrue,
          );
          expect(
            expands(
              note(
                'A recording with enough words to exceed its single preview row',
                type: NoteType.voice,
                duration: 3000,
              ),
            ),
            isTrue,
          );
        },
      );
    }
  }

  testWidgets('the same text can fit a wide card and overflow a narrow one', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final value = note(
      'First paragraph with a few words.\nبند دوم برای خواندن',
    );
    expect(nexNoteCanExpand(context, value, cardWidth: 760), isFalse);
    expect(nexNoteCanExpand(context, value, cardWidth: 220), isTrue);
  });
}
