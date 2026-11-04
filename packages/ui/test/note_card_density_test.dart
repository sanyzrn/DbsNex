import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Every collapsed kind shares the density envelope, including status marks.
void main() {
  Note note(
    NoteType type,
    String? content, {
    int? durationMs,
    bool carries = false,
  }) => Note(
    id: 'n-${type.name}-$carries',
    type: type,
    content: content,
    durationMs: durationMs,
    dueAt: carries ? DateTime.utc(2099) : null,
    attachmentCount: carries ? 2 : 0,
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
    // Ordinary marked notes share the unmarked height; structures keep a row.
    note(
      NoteType.text,
      'A thought long enough to need both lines of the card and then some '
      'more words after that, and more again past the third line too.',
      carries: true,
    ),
    note(NoteType.text, 'short', carries: true),
    note(
      NoteType.checklist,
      '- [ ] milk\n- [ ] bread\n- [x] eggs\n- [ ] tea',
      carries: true,
    ),
    note(NoteType.link, 'https://example.com/a/page', carries: true),
    note(NoteType.voice, 'what was said', durationMs: 42000, carries: true),
  ];

  for (final density in NexCardDensity.values) {
    testWidgets('${density.name}: all note kinds and marks share one height', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: NexCardDensityScope(
            density: density,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    children: [for (final n in notes) NoteCard(note: n)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final plain = <double>{};
      final inline = <double>{};
      final structured = <double>{};
      for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) {
        final height = tester.getSize(find.byWidget(card)).height;
        if (card.note.attachmentCount == 0) {
          plain.add(height);
        } else if (card.note.type == NoteType.text) {
          inline.add(height);
        } else {
          structured.add(height);
        }
      }
      expect(plain, hasLength(1));
      expect(inline, {plain.single});
      expect(structured, hasLength(1));
      expect(structured.single, plain.single);
      final expected =
          density.inset * 2 +
          [
            density.leading,
            density.lineHeight * density.lines,
          ].reduce((a, b) => a > b ? a : b) +
          density.cardInsets.vertical;
      expect(plain.single, expected);
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
