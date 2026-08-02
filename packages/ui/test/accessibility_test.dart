import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// The floor every interactive surface has to clear, as tests rather than as a
/// number in a token file that nothing consulted.
void main() {
  Tag tag(String name, {String? color}) => Tag(
    id: 't-$name',
    name: name,
    color: color,
    createdAt: DateTime.utc(2026),
  );

  Widget host(Widget child) => MaterialApp(
    theme: nexLightTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('every filter pill is at least a 48px target', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 400,
          child: TagFilterRow(
            tags: [
              tag('Work', color: '#F0A93B'),
              tag('Idea'),
            ],
            selectedTagId: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    // The pills were 34px tall and the type button 32 — under the token in
    // this package, under Material's 48 and under Apple's 44, on horizontally
    // scrolling targets, which is the hardest case for acquisition there is.
    for (final label in ['All', 'Work', 'Idea']) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(NexTappable),
      );
      expect(target, findsOneWidget, reason: '$label is not a NexTappable');
      expect(
        tester.getSize(target).height,
        greaterThanOrEqualTo(nexMinTapTarget),
        reason: '$label is under the tap-target floor',
      );
    }
  });

  testWidgets('a focused pill shows a ring, not a grey wash', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 400,
          child: TagFilterRow(
            tags: [tag('Work')],
            selectedTagId: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    ShapeDecoration decorationOf(String label) => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.ancestor(
              of: find.text(label),
              matching: find.byType(NexTappable),
            ),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<ShapeDecoration>()
        .first;

    expect(decorationOf('Work').shadows, isNull, reason: 'not focused yet');

    // Tab moves focus onto the first control.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final focused = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<ShapeDecoration>()
        .where((d) => d.shadows != null);
    expect(
      focused,
      isNotEmpty,
      reason: 'nothing on screen says where the keyboard is',
    );
    // A ring standing off the control, in the accent — not a fill tint, which
    // on a grey control against a grey ground is not perceivable.
    expect(
      focused.first.shadows!.first.color,
      nexLightTheme().colorScheme.primary,
    );
    expect(
      focused.first.shadows!.first.spreadRadius,
      nexFocusRingOffset + nexFocusRingWidth,
    );
  });

  testWidgets('a card announces itself in the language it was given', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final note = Note(
      id: 'n1',
      type: NoteType.voice,
      content: 'a thought',
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      tags: [tag('Work')],
    );

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 400,
          child: NoteCard(
            note: note,
            onTap: () {},
            // What the app injects, the way TagFilterRow.allLabel already is.
            // Built into the widget in English, a Persian user running
            // TalkBack heard the structure in one language and the content in
            // another.
            strings: NexCardStrings(
              noteOfType: (type) => 'یادداشت $type',
              tagList: (tags) => 'برچسب‌ها: $tags',
              accentColor: 'رنگ برچسب',
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('یادداشت')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('برچسب‌ها: Work')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a card is navigable inside, not one flat string', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final note = Note(
      id: 'n1',
      type: NoteType.text,
      content: 'the note body',
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      tags: [tag('Work')],
    );

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 400,
          child: NoteCard(note: note, onTap: () {}),
        ),
      ),
    );

    // `excludeSemantics` collapsed the whole card into one announcement, so a
    // screen-reader user could not reach the body or the tags separately. The
    // date is no longer on the card at all — it lives in the note's own sheet.
    expect(find.bySemanticsLabel(RegExp('the note body')), findsWidgets);
    expect(find.bySemanticsLabel('Tags: Work'), findsOneWidget);
    handle.dispose();
  });

  test('one glyph per note type, in one weight, from one place', () {
    // A photo note was Icons.image_outlined on its card and
    // Icons.photo_outlined in the type picker: the same concept with two marks.
    final icons = [
      for (final type in NoteType.values) nexNoteTypeIcon(type.wireName),
      nexNoteTypeIcon(null),
    ];
    expect(
      icons.toSet().length,
      icons.length,
      reason: 'two types share a mark',
    );
    // All outlined: three filled and two outlined in one five-row list reads as
    // unpolished before anyone can say why.
    for (final icon in icons) {
      expect(
        icon.fontFamily,
        'MaterialIcons',
        reason: 'the map is the only place a glyph is chosen',
      );
    }
  });
}
