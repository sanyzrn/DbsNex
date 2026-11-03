import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  final now = DateTime.utc(2026, 11, 3);
  Note note(String text, int marks, {String? caption}) => Note(
    id: 'note',
    type: NoteType.text,
    content: text,
    caption: caption,
    dueAt: marks & 1 != 0 ? now.add(const Duration(days: 1)) : null,
    attachmentCount: marks & 2 != 0 ? 3 : 0,
    isUrgent: marks & 4 != 0,
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );
  final strings = NexCardStrings(
    noteOfType: (s) => s,
    tagList: (s) => s,
    accentColor: 'Accent',
    dueLabel: (_, _) => 'Upcoming appointment tomorrow at 17:30',
    dueCompactLabel: (_, _) => 'Tomorrow',
    dueDescription: (_, _) => 'Full reminder description',
  );

  Future<void> pump(
    WidgetTester tester,
    Note value, {
    bool rtl = false,
    double scale = 1,
    NexCardDensity density = NexCardDensity.standard,
    bool expanded = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: rtl ? nexDarkTheme() : nexLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: NexCardDensityScope(
              density: density,
              child: SizedBox(
                width: 320,
                child: NoteCard(
                  note: value,
                  strings: strings,
                  expanded: expanded,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('inline marks keep the full reminder accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pump(
        tester,
        note('A note with a reminder and some long content', 7),
      );
      expect(
        find.bySemanticsLabel('Full reminder description'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final sample in [
    (false, 1.0, NexCardDensity.compact),
    (true, 1.8, NexCardDensity.compact),
    (false, 1.8, NexCardDensity.standard),
    (true, 1.0, NexCardDensity.standard),
    (false, 1.0, NexCardDensity.readable),
    (true, 1.8, NexCardDensity.readable),
    (false, 3.2, NexCardDensity.standard),
  ]) {
    testWidgets(
      '$sample all marker combinations retain equal height and safe last-line space',
      (tester) async {
        final (rtl, scale, density) = sample;
        final prefix = rtl ? 'متن مهم' : 'Important content';
        final text = List.filled(
          12,
          '$prefix with decisions 😀 and useful details',
        ).join(' ');
        double? height;
        for (var mask = 0; mask < 8; mask++) {
          await pump(
            tester,
            note(text, mask),
            rtl: rtl,
            scale: scale,
            density: density,
          );
          final card = find.byType(NoteCard);
          final rect = tester.getRect(card);
          height ??= rect.height;
          expect(rect.height, closeTo(height, 0.01));
          final paragraphs = tester.renderObjectList<RenderParagraph>(
            find.descendant(of: card, matching: find.byType(RichText)),
          );
          final words = paragraphs.firstWhere(
            (p) => mask == 0
                ? p.text
                      .toPlainText(includeSemanticsLabels: false)
                      .startsWith(prefix)
                : p.text
                      .toPlainText(includeSemanticsLabels: false)
                      .contains('\uFFFC'),
          );
          expect(
            words.size.height,
            greaterThan(
              nexCardPreviewLineHeightFor(tester.element(card)) *
                  (density.lines - 1),
            ),
          );
          if (mask == 0) continue;
          final plain = words.text.toPlainText(includeSemanticsLabels: false);
          final placeholder = plain.indexOf('\uFFFC');
          expect(placeholder, greaterThan(0));
          expect(plain, isNot(contains('\uFFFD')));
          final boxes = words.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: placeholder),
          );
          final origin = words.localToGlobal(Offset.zero);
          for (final icon in [
            Icons.notifications_active_outlined,
            Icons.attach_file,
            Icons.local_fire_department_outlined,
          ]) {
            for (final mark
                in find
                    .descendant(of: card, matching: find.byIcon(icon))
                    .evaluate()) {
              final markBox = mark.findRenderObject()! as RenderBox;
              final markRect =
                  markBox.localToGlobal(Offset.zero) & markBox.size;
              expect(rect.contains(markRect.center), isTrue);
              for (final box in boxes) {
                final overlap = box.toRect().shift(origin).intersect(markRect);
                expect(overlap.width > 0.5 && overlap.height > 0.5, isFalse);
              }
            }
          }
          if (mask & 2 != 0) {
            final count = tester.renderObject<RenderParagraph>(find.text('+3'));
            expect(count.didExceedMaxLines, isFalse);
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'a mixed preview keeps paragraph directions; Show in Full still grows',
    (tester) async {
      const text =
          'Hi\nمتن فارسی بلند با جزئیات فراوان و ادامهٔ توضیح برای خط آخر یادداشت';
      await pump(tester, note(text, 7));
      final small = tester.getSize(find.byType(NoteCard)).height;
      final pars = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        pars
            .firstWhere((p) => p.text.toPlainText().contains('Hi'))
            .textDirection,
        TextDirection.ltr,
      );
      expect(
        pars
            .firstWhere(
              (p) => p.text
                  .toPlainText(includeSemanticsLabels: false)
                  .contains('\uFFFC'),
            )
            .textDirection,
        TextDirection.rtl,
      );
      await pump(
        tester,
        note(List.filled(10, text).join('\n'), 7),
        expanded: true,
      );
      expect(tester.getSize(find.byType(NoteCard)).height, greaterThan(small));
      expect(tester.takeException(), isNull);
    },
  );
}
