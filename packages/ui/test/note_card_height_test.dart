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

  Tag tag(String name) => Tag(
        id: 't-$name',
        name: name,
        createdAt: DateTime.utc(2026),
      );

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

  testWidgets('every card is the same height, whatever it holds',
      (tester) async {
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

  testWidgets('a tag that does not fit runs off the edge rather than wrapping',
      (tester) async {
    // Wrapping to a second run of chips is what made a tagged card taller.
    await heightOf(
      tester,
      note(
        'short',
        tags: [
          for (final name in ['Work', 'Idea', 'Flutter', 'Learning', 'Later'])
            tag(name),
        ],
      ),
    );

    final dates = tester.getRect(find.text('Jul 28'));
    for (final name in ['Work', 'Idea']) {
      // Same line as the date: one row, however many tags there are.
      expect(
        tester.getRect(find.text(name)).center.dy,
        closeTo(dates.center.dy, 1),
      );
    }
  });

  testWidgets('the preview starts at the top, so one- and two-line notes align',
      (tester) async {
    await heightOf(tester, note('one line'));
    final short = tester.getRect(find.text('one line')).top;

    await heightOf(tester, note('a note that is long enough to take two lines '
        'in the card preview and therefore wraps'));
    final long = tester
        .getRect(find.textContaining('a note that is long enough'))
        .top;

    expect(long, closeTo(short, 0.5));
  });
}
