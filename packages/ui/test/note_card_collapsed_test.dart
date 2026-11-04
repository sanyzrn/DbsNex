import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  final at = DateTime.utc(2026, 11, 4);
  Note note(
    NoteType type,
    int mask, {
    String? caption,
    String? content,
  }) => Note(
    id: '${type.name}-$mask',
    type: type,
    content:
        content ??
        switch (type) {
          NoteType.link => 'https://example.com/long/article',
          NoteType.checklist =>
            '- [ ] Call the printer\n- [ ] Approve the colours\n- [x] Send brief',
          _ =>
            'Important content مهم 😀 with decisions and useful information. ' *
                8,
        },
    caption: caption,
    durationMs: type == NoteType.voice ? 42000 : null,
    dueAt: mask & 1 != 0 ? at.add(const Duration(days: 1)) : null,
    isUrgent: mask & 2 != 0,
    attachmentCount: mask & 4 != 0 ? 3 : 0,
    createdAt: at,
    updatedAt: at,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );
  final strings = NexCardStrings(
    noteOfType: (s) => s,
    tagList: (s) => s,
    accentColor: 'Accent',
    dueLabel: (_, _) => 'Appointment tomorrow at 17:30',
    dueCompactLabel: (_, _) => '1d',
    dueDescription: (_, _) => 'Full reminder description',
  );

  Future<void> pump(
    WidgetTester tester,
    Note value, {
    double width = 360,
    bool rtl = false,
    bool dark = false,
    TextScaler scaler = TextScaler.noScaling,
    NexCardDensity density = NexCardDensity.standard,
    bool expanded = false,
    bool showDue = true,
    bool? selected,
    Widget? override,
    NexCardStrings? cardStrings,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: dark ? nexDarkTheme() : nexLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: NexCardDensityScope(
              density: density,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: RepaintBoundary(
                    key: const ValueKey('card-boundary'),
                    child: NoteCard(
                      note: value,
                      strings: cardStrings ?? strings,
                      expanded: expanded,
                      showDue: showDue,
                      selected: selected,
                      previewOverride: override,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final config in [
    (360.0, false, false, NexCardDensity.compact, TextScaler.noScaling),
    (360.0, true, true, NexCardDensity.standard, TextScaler.noScaling),
    (220.0, false, true, NexCardDensity.compact, const TextScaler.linear(1.8)),
    (220.0, true, false, NexCardDensity.readable, const TextScaler.linear(1.8)),
    (320.0, true, true, NexCardDensity.standard, const TextScaler.linear(3.2)),
    (320.0, false, false, NexCardDensity.compact, const _NonLinearScaler()),
  ]) {
    testWidgets(
      '$config equal envelopes and full-width previews beneath bottom overlays',
      (tester) async {
        final (width, rtl, dark, density, scaler) = config;
        double? height;
        final widths = <NoteType, double>{};
        for (final type in NoteType.values) {
          for (var mask = 0; mask < 8; mask++) {
            for (final caption in [
              null,
              if (type == NoteType.text) 'توضیح ثانویه Secondary caption',
            ]) {
              await pump(
                tester,
                note(type, mask, caption: caption),
                width: width,
                rtl: rtl,
                dark: dark,
                density: density,
                scaler: scaler,
              );
              final card = tester.getRect(find.byType(NoteCard));
              height ??= card.height;
              expect(card.height, closeTo(height, .01));
              final body = tester.getRect(
                find.byKey(const ValueKey('note-card-preview')),
              );
              expect(body.bottom, lessThanOrEqualTo(card.bottom));
              widths.putIfAbsent(type, () => body.width);
              expect(body.width, closeTo(widths[type]!, .01));
              if (mask != 0) {
                final rail = tester.getRect(
                  find.byKey(const ValueKey('note-status-overlay')),
                );
                final rowHeight = nexCardPreviewLineHeightFor(
                  tester.element(find.byType(NoteCard)),
                );
                final cardContext = tester.element(find.byType(NoteCard));
                final bottom =
                    card.bottom -
                    nexCardInsetsFor(cardContext).bottom -
                    density.inset;
                expect(rail.bottom, closeTo(bottom, .01));
                expect(
                  rail.height,
                  lessThanOrEqualTo(rowHeight * 2 + NexSpacing.xs),
                );
                expect(
                  rtl ? rail.right : rail.left,
                  closeTo(rtl ? body.right : body.left, .01),
                );
                for (final icon in [
                  Icons.notifications_active_outlined,
                  Icons.local_fire_department_outlined,
                  Icons.attach_file,
                ]) {
                  for (final e in find.byIcon(icon).evaluate()) {
                    final box = e.findRenderObject()! as RenderBox;
                    final rect = box.localToGlobal(Offset.zero) & box.size;
                    expect(card.contains(rect.topLeft), isTrue);
                    expect(card.contains(rect.bottomRight), isTrue);
                    expect(rail.contains(rect.center), isTrue);
                  }
                }
                if (mask & 4 != 0) expect(find.text('+3'), findsOneWidget);
              }
              if (caption != null) {
                final cap = tester.getRect(
                  find.byKey(const ValueKey('note-card-caption')),
                );
                expect(cap.top, greaterThanOrEqualTo(body.bottom));
                expect(cap.bottom, lessThanOrEqualTo(card.bottom));
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(
                    of: find.byKey(const ValueKey('note-card-caption')),
                    matching: find.byType(RichText),
                  ),
                );
                expect(
                  paragraph.size.height,
                  greaterThanOrEqualTo(
                    paragraph.getMaxIntrinsicHeight(paragraph.size.width) - .01,
                  ),
                );
              }
              expect(
                tester.takeException(),
                isNull,
                reason: '$type, marks=$mask, caption=$caption',
              );
            }
          }
        }
      },
    );
  }

  for (final rtl in [false, true]) {
    testWidgets(
      '$rtl existing marks pack in order, with a fixed start and no holes',
      (tester) async {
        Offset? anchor;
        for (var mask = 1; mask < 8; mask++) {
          await pump(
            tester,
            note(
              NoteType.text,
              mask,
              content: mask.isEven ? 'متن فارسی' : 'English',
            ),
            width: 480,
            rtl: rtl,
          );
          final rail = tester.getRect(
            find.byKey(const ValueKey('note-status-overlay')),
          );
          final start = Offset(rtl ? rail.right : rail.left, rail.top);
          anchor ??= start;
          expect(start, anchor);
          final icons = [
            if (mask & 1 != 0) Icons.notifications_active_outlined,
            if (mask & 2 != 0) Icons.local_fire_department_outlined,
            if (mask & 4 != 0) Icons.attach_file,
          ].map((icon) => tester.getRect(find.byIcon(icon))).toList();
          expect(
            rtl ? icons.first.right : icons.first.left,
            closeTo(start.dx, 1),
          );
          for (var i = 1; i < icons.length; i++) {
            expect(icons[i].center.dy, closeTo(icons.first.center.dy, 1));
            expect(
              rtl
                  ? icons[i].right < icons[i - 1].left
                  : icons[i].left > icons[i - 1].right,
              isTrue,
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final rtl in [false, true]) {
    testWidgets(
      '$rtl compact reminder clock fits beside other marks at large text',
      (tester) async {
        final clock = rtl ? '۰۹:۰۵' : '09:05';
        final schedule = rtl ? 'هر روز · $clock' : 'Daily · $clock';
        final cardStrings = NexCardStrings(
          noteOfType: (s) => s,
          tagList: (s) => s,
          accentColor: 'Accent',
          dueLabel: (_, _) => schedule,
          dueCompactLabel: (_, _) => clock,
          dueDescription: (_, _) => schedule,
        );
        await pump(
          tester,
          note(NoteType.text, 0),
          width: 320,
          rtl: rtl,
          scaler: const TextScaler.linear(1.9),
        );
        final height = tester.getSize(find.byType(NoteCard)).height;
        await pump(
          tester,
          note(NoteType.text, 7),
          width: 320,
          rtl: rtl,
          scaler: const TextScaler.linear(1.9),
          cardStrings: cardStrings,
        );
        expect(tester.getSize(find.byType(NoteCard)).height, height);
        expect(find.text(clock), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(clock),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          nexNoteCanExpand(
            tester.element(find.byType(NoteCard)),
            note(NoteType.text, 7, content: 'Short'),
            cardWidth: 320,
            strings: cardStrings,
          ),
          isTrue,
        );

        final attachment = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text('+3'), matching: find.byType(RichText)),
        );
        expect(attachment.didExceedMaxLines, isFalse);
        final clockBounds = tester.getRect(find.text(clock));
        final urgentBounds = tester.getRect(
          find.byIcon(Icons.local_fire_department_outlined),
        );
        final attachmentBounds = tester.getRect(find.text('+3'));
        expect(clockBounds.overlaps(urgentBounds), isFalse);
        expect(clockBounds.overlaps(attachmentBounds), isFalse);
        expect(urgentBounds.overlaps(attachmentBounds), isFalse);
        final preview = tester.getRect(
          find.byKey(const ValueKey('note-card-preview')),
        );
        expect(preview.overlaps(clockBounds), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      '$dark caption is distinct secondary grey with readable contrast',
      (tester) async {
        await pump(
          tester,
          note(NoteType.text, 7, caption: 'کپشن Caption'),
          dark: dark,
        );
        final element = tester.element(
          find.byKey(const ValueKey('note-card-caption')),
        );
        final caption = tester.widget<NexTextSurface>(
          find.byKey(const ValueKey('note-card-caption')),
        );
        final theme = Theme.of(element);
        expect(caption.style!.color, theme.colorScheme.onSurfaceVariant);
        expect(caption.style!.color, isNot(theme.colorScheme.onSurface));
        final a = caption.style!.color!.computeLuminance();
        final b = theme.colorScheme.surfaceContainerLowest.computeLuminance();
        expect(
          (b > a ? (b + .05) / (a + .05) : (a + .05) / (b + .05)),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }

  testWidgets(
    'reminder schedule remains accessible even with an icon-only rail',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, note(NoteType.text, 7), width: 220);
      expect(
        find.bySemanticsLabel('Full reminder description'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'mixed paragraphs keep their direction and explicit expansion grows',
    (tester) async {
      const text = 'Hi\nمتن فارسی';
      await pump(tester, note(NoteType.text, 7, content: text));
      final short = tester.getSize(find.byType(NoteCard)).height;
      for (final (words, direction) in [
        ('Hi', TextDirection.ltr),
        ('متن فارسی', TextDirection.rtl),
      ]) {
        final p = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .firstWhere((p) => p.text.toPlainText() == words);
        expect(p.textDirection, direction);
      }
      await pump(
        tester,
        note(NoteType.text, 7, content: '$text\n' * 10),
        expanded: true,
      );
      expect(tester.getSize(find.byType(NoteCard)).height, greaterThan(short));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom previews and hidden reminders keep the same envelope', (
    tester,
  ) async {
    await pump(tester, note(NoteType.text, 0));
    final height = tester.getSize(find.byType(NoteCard)).height;
    await pump(
      tester,
      note(NoteType.text, 7),
      override: const Text('Custom preview'),
    );
    expect(tester.getSize(find.byType(NoteCard)).height, height);
    expect(find.text('Custom preview'), findsOneWidget);
    await pump(tester, note(NoteType.text, 1), showDue: false);
    expect(find.byKey(const ValueKey('note-status-overlay')), findsNothing);
    expect(tester.getSize(find.byType(NoteCard)).height, height);
  });

  for (final density in NexCardDensity.values) {
    for (final rtl in [false, true]) {
      testWidgets('${density.name} $rtl marks never reflow or narrow text', (
        tester,
      ) async {
        final text =
            (rtl
                ? 'این متن برای بررسی چیدمان یادداشت طولانی است '
                : 'This long note checks that the full text keeps its natural wrapping. ') *
            8;
        Size? size;
        List<Rect>? boxes;
        for (final mask in [0, 1, 2, 4, 7]) {
          await pump(
            tester,
            note(NoteType.text, mask, content: text),
            density: density,
            rtl: rtl,
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('note-card-preview')),
                  matching: find.byType(RichText),
                )
                .first,
          );
          final actual = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: text.length),
              )
              .map((b) => b.toRect())
              .toList();
          size ??= paragraph.size;
          boxes ??= actual;
          expect(paragraph.size, size);
          expect(actual, boxes);
          expect(actual.map((b) => b.top).toSet(), hasLength(density.lines));
          final fullWidth = tester
              .getSize(find.byKey(const ValueKey('note-card-preview')))
              .width;
          expect(paragraph.size.width, closeTo(fullWidth, .01));
          if (mask != 0) {
            final overlay = tester.getRect(
              find.byKey(const ValueKey('note-status-overlay')),
            );
            final preview = tester.getRect(
              find.byKey(const ValueKey('note-card-preview')),
            );
            final row = nexCardPreviewLineHeightFor(
              tester.element(find.byType(NoteCard)),
            );
            expect(overlay.top, greaterThanOrEqualTo(preview.bottom - row));
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('short text stays above the status overlay at every density', (
    tester,
  ) async {
    for (final density in NexCardDensity.values) {
      for (final rtl in [false, true]) {
        await pump(
          tester,
          note(NoteType.text, 7, content: rtl ? 'متن کوتاه' : 'A short note'),
          density: density,
          rtl: rtl,
        );
        final paragraph = find
            .descendant(
              of: find.byKey(const ValueKey('note-card-preview')),
              matching: find.byType(RichText),
            )
            .first;
        final overlay = tester.getRect(
          find.byKey(const ValueKey('note-status-overlay')),
        );
        expect(tester.getRect(paragraph).overlaps(overlay), isFalse);
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        '$rtl $dark overlay matches selected surface and fades outward',
        (tester) async {
          for (final selected in [false, true]) {
            await pump(
              tester,
              note(NoteType.text, 6),
              rtl: rtl,
              dark: dark,
              selected: selected,
            );
            final fill = tester.widget<ColoredBox>(
              find.byKey(const ValueKey('note-status-fill')),
            );
            final material = tester.widget<Material>(
              find
                  .descendant(
                    of: find.byType(NoteCard),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(fill.color, material.color);
            final fade = tester.widget<Container>(
              find.byKey(const ValueKey('note-status-fade')),
            );
            final gradient =
                (fade.decoration! as BoxDecoration).gradient! as LinearGradient;
            expect(gradient.colors, [
              fill.color,
              fill.color.withValues(alpha: 0),
            ]);
            final direction = rtl ? TextDirection.rtl : TextDirection.ltr;
            expect(
              gradient.begin.resolve(direction),
              rtl ? Alignment.centerRight : Alignment.centerLeft,
            );
            final overlay = tester.getSize(
              find.byKey(const ValueKey('note-status-overlay')),
            );
            final marks = tester.getSize(
              find.byKey(const ValueKey('note-status-marks')),
            );
            expect(
              overlay.width,
              closeTo(marks.width + 16 + NexSpacing.xs, .01),
            );
          }
        },
      );
    }
  }

  testWidgets(
    'solid overlay hides preview pixels and its edge blends smoothly',
    (tester) async {
      const underlay = Color(0xFFFF00FF);
      for (final rtl in [false, true]) {
        await pump(
          tester,
          note(NoteType.text, 2),
          rtl: rtl,
          override: const SizedBox.expand(child: ColoredBox(color: underlay)),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('card-boundary')),
        );
        final fill = tester.getRect(
          find.byKey(const ValueKey('note-status-fill')),
        );
        final fade = tester.getRect(
          find.byKey(const ValueKey('note-status-fade')),
        );
        final origin = boundary.localToGlobal(Offset.zero);
        final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        );
        final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        Color pixel(Offset point) {
          final local = point - origin;
          final offset =
              (local.dy.floor() * image!.width + local.dx.floor()) * 4;
          return Color.fromARGB(
            255,
            bytes!.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        }

        final color = tester
            .widget<ColoredBox>(find.byKey(const ValueKey('note-status-fill')))
            .color;
        expect(
          pixel(Offset(rtl ? fill.left + 1 : fill.right - 1, fill.center.dy)),
          color,
        );
        final near = pixel(
          Offset(rtl ? fade.right - 1 : fade.left + 1, fade.top + 1),
        );
        final far = pixel(
          Offset(rtl ? fade.left + 1 : fade.right - 1, fade.top + 1),
        );
        expect(near, isNot(underlay));
        expect(far, isNot(color));
        expect(near.g, greaterThan(far.g));
        image!.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Show in full exposes masked text without treating every short note as expandable',
    (tester) async {
      final short = note(NoteType.text, 7, content: 'Short');
      await pump(tester, short, width: 600);
      final context = tester.element(find.byType(NoteCard));
      expect(nexNoteCanExpand(context, short, cardWidth: 600), isFalse);
      expect(
        nexNoteCanExpand(
          context,
          short.copyWith(content: 'First line\nSecond line'),
          cardWidth: 600,
        ),
        isTrue,
      );
      expect(
        nexNoteCanExpand(
          context,
          short.copyWith(caption: 'Caption'),
          cardWidth: 600,
        ),
        isTrue,
      );
    },
  );

  testWidgets('Show in full accounts for the caption preview budget', (
    tester,
  ) async {
    final value = note(NoteType.text, 0, content: 'First line\nSecond line');
    await pump(tester, value, width: 600);
    final context = tester.element(find.byType(NoteCard));
    expect(nexNoteCanExpand(context, value, cardWidth: 600), isFalse);
    final captioned = value.copyWith(caption: 'Secondary caption');
    expect(nexNoteCanExpand(context, captioned, cardWidth: 600), isTrue);
  });
}

class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();
  @override
  double scale(double size) => size + 4.2;
  @override
  double get textScaleFactor => scale(14) / 14;
}
