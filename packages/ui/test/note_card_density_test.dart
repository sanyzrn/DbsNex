import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// W7.2: every card, every density — the same height as its neighbours and
/// nothing spilling out of it.
void main() {
  Note note(NoteType type, String? content, {int? durationMs}) => Note(
    id: 'n-${type.name}',
    type: type,
    content: content,
    durationMs: durationMs,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  final notes = [
    note(
      NoteType.text,
      'A thought long enough to need both lines of the card and then some '
      'more words after that, and more again past the third line too.',
    ),
    note(NoteType.checklist, '- [ ] milk\n- [ ] bread\n- [x] eggs\n- [ ] tea'),
    note(NoteType.link, 'https://example.com/a/page'),
    note(NoteType.voice, 'what was said', durationMs: 42000),
  ];

  for (final density in NexCardDensity.values) {
    testWidgets('${density.name}: one height, no overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: NexCardDensityScope(
            density: density,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: Column(
                  children: [for (final n in notes) NoteCard(note: n)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final heights = {
        for (final card in tester.widgetList(find.byType(NoteCard)))
          tester.getSize(find.byWidget(card)).height,
      };
      expect(heights, hasLength(1), reason: 'every card the same height');
      final expected =
          density.inset * 2 +
          [
            density.leading,
            density.lineHeight * density.lines,
          ].reduce((a, b) => a > b ? a : b) +
          density.cardInsets.vertical;
      expect(heights.single, expected);
    });
  }

  test('compact is shorter than standard, readable taller', () {
    double height(NexCardDensity d) =>
        d.inset * 2 +
        [d.leading, d.lineHeight * d.lines].reduce((a, b) => a > b ? a : b);
    expect(
      height(NexCardDensity.compact),
      lessThan(height(NexCardDensity.standard)),
    );
    expect(
      height(NexCardDensity.readable),
      greaterThan(height(NexCardDensity.standard)),
    );
    expect(NexCardDensity.fromWire('nonsense'), NexCardDensity.standard);
  });

  test('only compact draws the cards closer together', () {
    expect(NexCardDensity.standard.cardInsets, nexCardInsets);
    expect(NexCardDensity.readable.cardInsets, nexCardInsets);
    expect(
      NexCardDensity.compact.cardInsets.vertical,
      lessThan(nexCardInsets.vertical),
    );
    // The side gutter stays: the swipe panel and the day headings line up
    // with it.
    expect(
      NexCardDensity.compact.cardInsets.horizontal,
      nexCardInsets.horizontal,
    );
  });
}
