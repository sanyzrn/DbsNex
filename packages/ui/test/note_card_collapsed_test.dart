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
    Widget? override,
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
                  child: NoteCard(
                    note: value,
                    strings: strings,
                    expanded: expanded,
                    showDue: showDue,
                    previewOverride: override,
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
    testWidgets('$config equal envelopes and separate readable regions', (
      tester,
    ) async {
      final (width, rtl, dark, density, scaler) = config;
      double? height;
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
            if (mask != 0) {
              final rail = tester.getRect(
                find.byKey(const ValueKey('note-status-rail')),
              );
              expect(body.overlaps(rail), isFalse);
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
                  expect(body.overlaps(rect), isFalse);
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
    });
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
            find.byKey(const ValueKey('note-status-rail')),
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
    expect(find.byKey(const ValueKey('note-status-rail')), findsNothing);
    expect(tester.getSize(find.byType(NoteCard)).height, height);
  });

  testWidgets('Show in full accounts for the caption preview budget', (
    tester,
  ) async {
    final value = note(NoteType.text, 7, content: 'First line\nSecond line');
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
