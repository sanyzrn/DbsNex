import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// W7.2: every card, every density — the same height as its neighbours and
/// nothing spilling out of it.
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
    // A reminder and attachments: the footnote under the words still fits.
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
    testWidgets('${density.name}: one height, no overflow', (tester) async {
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

  // The marks sit where the words end, on their own line: on the right
  // after English words, on the left after Persian ones — and a short note
  // carries them on its one line, so they cost the card no line.
  for (final (text, right) in [
    ('Call the plumber', true),
    ('قبض برق', false),
  ]) {
    testWidgets('the marks sit where "$text" ends, on its line', (
      tester,
    ) async {
      final carrying = Note(
        id: 'n',
        type: NoteType.text,
        content: text,
        dueAt: DateTime.utc(2099),
        attachmentCount: 2,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: Scaffold(
            body: SizedBox(width: 400, child: NoteCard(note: carrying)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(NoteCard));
      final bell = tester.getCenter(
        find.byIcon(Icons.notifications_active_outlined),
      );
      expect(bell.dx > card.center.dx, right);
      final words = tester.getCenter(find.text(text));
      expect((bell.dy - words.dy).abs(), lessThan(4), reason: 'same line');
    });
  }

  testWidgets('a long note keeps both its lines beside the marks', (
    tester,
  ) async {
    const long =
        'A thought long enough to need both lines of the card and then some '
        'more words after that, and more again past the third line too.';
    Note make({required bool carries}) => Note(
      id: 'n$carries',
      type: NoteType.text,
      content: long,
      dueAt: carries ? DateTime.utc(2099) : null,
      attachmentCount: carries ? 2 : 0,
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              children: [
                NoteCard(note: make(carries: false)),
                NoteCard(note: make(carries: true)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final heights = [
      for (final element in find.text(long).evaluate())
        tester.getSize(find.byWidget(element.widget)).height,
    ];
    expect(heights, hasLength(2));
    expect(heights.last, heights.first);
  });
}
