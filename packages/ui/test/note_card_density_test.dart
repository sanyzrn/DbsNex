import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Ordinary collapsed previews share their height with inline status marks.
/// Structured previews keep a separate row; neither may overlap the words.
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
    testWidgets('${density.name}: full preview and room for status marks', (
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
      expect(structured.single, greaterThan(plain.single));
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

  for (final direction in TextDirection.values) {
    testWidgets('inline marks respect note and app directions in $direction', (
      tester,
    ) async {
      for (final text in ['Call the plumber', 'قبض برق', '۹ am: جلسه']) {
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
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SizedBox(width: 400, child: NoteCard(note: carrying)),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final bell = tester.getRect(
          find.byIcon(Icons.notifications_active_outlined),
        );
        final clip = tester.getRect(find.byIcon(Icons.attach_file));
        final words = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .singleWhere(
              (p) => p.text
                  .toPlainText(includeSemanticsLabels: false)
                  .contains('\uFFFC'),
            );
        expect(
          words.text.toPlainText(includeSemanticsLabels: false),
          '$text\uFFFC',
        );
        expect(words.textDirection, nexDirectionOf(text) ?? direction);
        expect(clip.center.dy, closeTo(bell.center.dy, 1));
        final origin = words.localToGlobal(Offset.zero);
        for (final box in words.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        )) {
          final rect = box.toRect().shift(origin);
          expect(bell.overlaps(rect), isFalse);
          expect(clip.overlaps(rect), isFalse);
        }
        expect(
          direction == TextDirection.ltr
              ? bell.left < clip.left
              : bell.left > clip.left,
          isTrue,
        );
      }
    });
  }

  testWidgets('a long note reserves only the last-line tail for marks', (
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
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .where(
          (p) => p.text
              .toPlainText(includeSemanticsLabels: false)
              .startsWith('A thought'),
        )
        .toList();
    expect(paragraphs, hasLength(2));
    expect(paragraphs.last.size.height, paragraphs.first.size.height);
    final rows = paragraphs.map((p) {
      final text = p.text.toPlainText(includeSemanticsLabels: false);
      final end = text.contains('\uFFFC')
          ? text.indexOf('\uFFFC')
          : text.length;
      return p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: end),
      );
    }).toList();
    expect(rows.first.map((b) => b.top).toSet(), hasLength(2));
    expect(rows.last.map((b) => b.top).toSet(), hasLength(2));
    expect(rows.last.first.toRect().width, rows.first.first.toRect().width);
    expect(
      rows.last.last.toRect().width,
      lessThan(rows.first.last.toRect().width),
    );
  });
  for (final density in NexCardDensity.values) {
    for (final scale in [1.0, 1.9]) {
      testWidgets(
        '${density.name}: safe marks at scale $scale on a narrow card',
        (tester) async {
          for (final direction in TextDirection.values) {
            for (final dark in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? nexDarkTheme() : nexLightTheme(),
                  home: Directionality(
                    textDirection: direction,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: NexCardDensityScope(
                        density: density,
                        child: Scaffold(
                          body: SizedBox(
                            width: 320,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final n in notes.where(
                                    (n) => n.attachmentCount > 0,
                                  ))
                                    NoteCard(
                                      note: n,
                                      strings: NexCardStrings(
                                        noteOfType: (type) => type,
                                        tagList: (tags) => tags,
                                        accentColor: 'Accent',
                                        dueLabel: (_, _) =>
                                            direction == TextDirection.rtl
                                            ? 'تکرار هر روز صبح'
                                            : 'Every morning, repeating',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              expect(tester.takeException(), isNull);
              for (final element in find.byType(NoteCard).evaluate()) {
                final card = find.byWidget(element.widget);
                final bell = tester.getRect(
                  find.descendant(
                    of: card,
                    matching: find.byIcon(Icons.notifications_active_outlined),
                  ),
                );
                final clip = tester.getRect(
                  find.descendant(
                    of: card,
                    matching: find.byIcon(Icons.attach_file),
                  ),
                );
                final bounds = tester.getRect(card);
                expect(bell.center.dy, closeTo(clip.center.dy, 1));
                expect(bounds.contains(bell.topLeft), isTrue);
                expect(bounds.contains(clip.bottomRight), isTrue);
                final noteCard = element.widget as NoteCard;
                if (noteCard.note.type == NoteType.text) {
                  final words = tester
                      .renderObjectList<RenderParagraph>(
                        find.descendant(
                          of: card,
                          matching: find.byType(RichText),
                        ),
                      )
                      .singleWhere(
                        (p) => p.text
                            .toPlainText(includeSemanticsLabels: false)
                            .contains('\uFFFC'),
                      );
                  final text = words.text.toPlainText(
                    includeSemanticsLabels: false,
                  );
                  final origin = words.localToGlobal(Offset.zero);
                  for (final box in words.getBoxesForSelection(
                    TextSelection(
                      baseOffset: 0,
                      extentOffset: text.indexOf('\uFFFC'),
                    ),
                  )) {
                    final rect = box.toRect().shift(origin);
                    expect(bell.overlaps(rect), isFalse);
                    expect(clip.overlaps(rect), isFalse);
                  }
                }
                for (final text
                    in find
                        .descendant(
                          of: card,
                          matching: find.byType(NexTextSurface),
                        )
                        .evaluate()) {
                  final words = tester.getRect(find.byWidget(text.widget));
                  expect(words.bottom, lessThanOrEqualTo(bell.top));
                }
              }
            }
          }
        },
      );
    }
  }
}
