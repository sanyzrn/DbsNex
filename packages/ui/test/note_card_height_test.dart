import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Cards used to size to their content: a note carrying tags stood taller than
/// one without, and two lines of text taller than one. Nothing about that
/// height told the reader anything, and the list came out ragged.
void main() {
  Note note(String content, {List<Tag> tags = const []}) {
    final now = DateTime.utc(2026, 7, 28);
    return Note(
      id: 'n-${content.hashCode}',
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      tags: tags,
    );
  }

  Tag tag(String name) =>
      Tag(id: 't-$name', name: name, createdAt: DateTime.utc(2026));

  Future<double> heightOf(WidgetTester tester, Note value) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: NoteCard(note: value)),
        ),
      ),
    );
    return tester.getSize(find.byType(NoteCard)).height;
  }

  testWidgets('every card is the same height, whatever it holds', (
    tester,
  ) async {
    final short = await heightOf(tester, note('one line'));
    final long = await heightOf(
      tester,
      note(
        'a note long enough to wrap onto a second line and then keep going '
        'well past the end of it, so the preview is truncated',
      ),
    );
    final tagged = await heightOf(
      tester,
      note('one line', tags: [tag('Work'), tag('Idea'), tag('Flutter')]),
    );
    final both = await heightOf(
      tester,
      note(
        'a note long enough to wrap onto a second line and keep going',
        tags: [tag('Work'), tag('Idea'), tag('Flutter'), tag('Learning')],
      ),
    );

    expect(short, long);
    expect(short, tagged);
    expect(short, both);
    // The card's own box plus the gutter it sits in.
    expect(short, nexCardHeight + nexCardInsets.vertical);
  });

  testWidgets('a pinned note shows a pin, an unpinned one does not', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 28);
    final pinned = Note(
      id: 'pinned',
      type: NoteType.text,
      content: 'pinned note',
      createdAt: now,
      updatedAt: now,
      pinnedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );

    await heightOf(tester, note('not pinned'));
    expect(find.byIcon(Icons.push_pin), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: NoteCard(note: pinned)),
        ),
      ),
    );
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('tags are colours on the card, never names', (tester) async {
    // The name is already in the note's own words and in its detail sheet; on
    // the card it competed with the first line for the same glance, and three
    // of them filled the row.
    await heightOf(tester, note('short', tags: [tag('Work'), tag('Idea')]));

    expect(find.text('Work'), findsNothing);
    expect(find.text('Idea'), findsNothing);
    expect(find.text('Jul 28'), findsNothing, reason: 'the date moved too');
  });

  testWidgets('a tag with no colour still leaves a mark', (tester) async {
    // Otherwise "this note is tagged" would depend on the user having chosen
    // a colour, and an untagged note and an uncoloured-tag note would read
    // identically.
    await heightOf(tester, note('untagged'));
    final bare = tester.widgetList(find.byType(Container)).length;

    await heightOf(tester, note('tagged', tags: [tag('Work')]));
    expect(tester.widgetList(find.byType(Container)).length, greaterThan(bare));
  });

  testWidgets('the glyph sits in equal insets, top and bottom', (tester) async {
    // It used to have 16 above it and 48 below, which is why the card read as
    // top-weighted: it was.
    await heightOf(tester, note('one line'));
    final card = tester.getRect(find.byType(NoteCard));
    final glyph = tester.getRect(find.byIcon(nexNoteTypeIcon('text')).first);

    // The icon is centred in its box, so measure the box's edges from it.
    final above = glyph.center.dy - (card.top + nexCardInsets.top);
    final below = (card.bottom - nexCardInsets.bottom) - glyph.center.dy;
    expect(above, closeTo(below, 0.5));
  });

  testWidgets(
    'the leading icon box is rounder than the old concentric radius, and borderless',
    (tester) async {
      await heightOf(tester, note('one line'));
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(nexNoteTypeIcon('text')).first,
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
      final radius = decoration.borderRadius! as BorderRadius;
      expect(radius, BorderRadius.circular(NexRadius.cardLeading));
      // The old NexRadius.inside(lg, cardInset) floored out at 4px — this is
      // meant to be visibly rounder than that.
      expect(NexRadius.cardLeading, greaterThan(4));
    },
  );

  testWidgets('the preview wraps to two lines and stops there', (tester) async {
    // Two, not one: one line was enough to tell cards apart and not enough to
    // tell you what a note said. The card did not have to grow for it — the
    // second line fits in the height the leading glyph already reserved, once
    // the timestamp stops sitting underneath.
    await heightOf(
      tester,
      note(
        'a note that is long enough to take two lines in the card '
        'preview and therefore wraps, and then keeps going well past '
        'the end of the second line so that it has to be truncated',
      ),
    );
    final rect = tester.getRect(
      find.textContaining('a note that is long enough'),
    );
    // Two lines of bodyLarge (24px each), and no third.
    expect(rect.height, closeTo(48, 1));
  });

  testWidgets('the timestamp sits between the glyph and the preview', (
    tester,
  ) async {
    // It used to be stacked under the preview, which is what forced the card
    // taller the moment the preview took two lines — height spent on the least
    // important thing on the card. Beside the glyph it costs nothing
    // vertically, and it doubles as the gap holding the text off the glyph.
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: NoteCard(
              note: Note(
                id: 'fresh',
                type: NoteType.text,
                content: 'one line',
                createdAt: now,
                updatedAt: now,
                deviceId: 'test',
                rev: 1,
                syncState: SyncState.pending,
              ),
            ),
          ),
        ),
      ),
    );

    final card = tester.getRect(find.byType(NoteCard));
    final glyph = tester.getRect(find.byIcon(nexNoteTypeIcon('text')).first);
    final time = tester.getRect(find.text('now'));
    final preview = tester.getRect(find.text('one line'));

    // Glyph, then time, then text — in that order across the card.
    expect(time.left, greaterThan(glyph.right));
    expect(preview.left, greaterThan(time.right));
    // All three on one centre line.
    expect(time.center.dy, closeTo(card.center.dy, 1));
    expect(preview.center.dy, closeTo(card.center.dy, 1));
  });

  testWidgets('two lines of preview cost the card no extra height', (
    tester,
  ) async {
    // The regression this guards: the preview went to two lines and the card
    // grew to fit both them and a timestamp stacked underneath. Two lines of
    // bodyLarge come to exactly what the leading glyph already reserved, so
    // the card's height never had to move.
    final height = await heightOf(
      tester,
      note(
        'a note long enough to wrap onto a second line and then keep going '
        'well past the end of it, so the preview is truncated',
      ),
    );

    expect(height, nexCardHeight + nexCardInsets.vertical);
    expect(nexCardHeight, nexCardLeadingSize + NexSpacing.cardInset * 2);
  });

  testWidgets('a card grows only when larger text actually needs it', (
    tester,
  ) async {
    // The one case where the card must move: someone has turned the text size
    // up, two preview lines outgrow the glyph, and a fixed box would clip
    // them. Anything at or below the default is left exactly where it was.
    Future<double> at(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(width: 400, child: NoteCard(note: note('x'))),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(NoteCard)).height;
    }

    final normal = await at(1);
    expect(normal, nexCardHeight + nexCardInsets.vertical);
    // Smaller text does not shrink it below the glyph it still has to hold.
    expect(await at(0.8), normal);
    expect(await at(1.4), greaterThan(normal));
  });
}
