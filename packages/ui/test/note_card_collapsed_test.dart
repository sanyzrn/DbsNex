import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  final at = DateTime.utc(2099);
  Note note(
    int mask, {
    String? content,
    String? caption,
    NoteType type = NoteType.text,
    List<Tag> tags = const [],
  }) => Note(
    id: 'n',
    type: type,
    content: content ?? 'A long thought with useful words. ' * 16,
    caption: caption,
    dueAt: mask & 1 != 0 ? at : null,
    attachmentCount: mask & 2 != 0 ? 3 : 0,
    isUrgent: mask & 4 != 0,
    createdAt: at,
    updatedAt: at,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    tags: tags,
  );
  Tag tag(int i) => Tag(
    id: 't$i',
    name: 'Tag $i',
    color: ['#0E9384', '#E5502D', '#7357E8'][i % 3],
    createdAt: at,
  );
  final strings = NexCardStrings(
    noteOfType: (s) => s,
    tagList: (s) => s,
    accentColor: 'Accent',
    dueLabel: (_, _) => '2d',
    dueDescription: (_, _) => 'Full reminder schedule',
  );
  Future<void> pump(
    WidgetTester tester,
    Note value, {
    bool rtl = false,
    bool dark = false,
    bool? selected,
    bool ringing = false,
    NexCardDensity density = NexCardDensity.standard,
    double width = 360,
    double scale = 1,
    Widget? preview,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: dark ? nexDarkTheme() : nexLightTheme(),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: NexCardDensityScope(
              density: density,
              child: SizedBox(
                width: width,
                child: NoteCard(
                  note: value,
                  strings: strings,
                  selected: selected,
                  ringing: ringing,
                  onTap: () {},
                  previewOverride: preview,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Finder badge(String id) => find.byKey(ValueKey('note-status-orbit-$id'));

  for (final rtl in [false, true]) {
    for (final density in NexCardDensity.values) {
      testWidgets('$rtl $density: previews stay vertically centred', (
        tester,
      ) async {
        for (var lines = 1; lines <= density.lines; lines++) {
          final content = List.filled(
            lines,
            rtl ? 'متن فارسی' : 'A short line',
          ).join('\n');
          for (final type in [NoteType.text, NoteType.file]) {
            await pump(
              tester,
              note(0, content: content, type: type),
              rtl: rtl,
              density: density,
            );
            final text = tester.getRect(find.text(content));
            final area = tester.getRect(
              find.byKey(const ValueKey('note-card-preview')),
            );
            expect(text.center.dy, closeTo(area.center.dy, .01));
            expect(tester.takeException(), isNull);
          }
        }
      });

      testWidgets('$rtl $density: one to three badges follow the lower arc', (
        tester,
      ) async {
        Size? previewSize;
        double? height;
        for (var mask = 0; mask < 8; mask++) {
          final value = note(mask);
          await pump(tester, value, rtl: rtl, density: density);
          final p = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('note-card-preview')),
                  matching: find.byType(RichText),
                )
                .first,
          );
          previewSize ??= p.size;
          height ??= tester.getSize(find.byType(NoteCard)).height;
          expect(p.size, previewSize);
          expect(tester.getSize(find.byType(NoteCard)).height, height);
          expect(find.text('2d'), findsNothing);
          expect(find.text('+3'), findsNothing);
          expect(find.byType(ShaderMask), findsNothing);
          final ids = [
            if (mask & 2 != 0) 'attachment',
            if (mask & 4 != 0) 'urgent',
            if (mask & 1 != 0) 'reminder',
          ];
          final orb = tester.getRect(
            find.byKey(const ValueKey('note-leading-orbit')),
          );
          final positions = <double>[];
          for (final id in ids) {
            final rect = tester.getRect(badge(id));
            // Layout transforms can introduce sub-pixel floating-point noise.
            final normalSide = switch (density) {
              NexCardDensity.compact => 14.0,
              NexCardDensity.standard => 16.0,
              NexCardDensity.readable => 18.0,
            };
            final markSide = ids.length == 3
                ? math.min(normalSide, density.leading / 3 - 2)
                : normalSide;
            expect(rect.width, closeTo(markSide, 0.01));
            expect(rect.height, closeTo(markSide, 0.01));
            expect(rect.center.dy, greaterThan(orb.center.dy));
            // Unlike the previous design, the circle is never shrunk when
            // status marks appear. Each white disc sits on its lower rim.
            final circle = tester.getRect(
              find.byKey(const ValueKey('note-main-circle-paint')),
            );
            expect(circle.width, closeTo(density.leading, 0.01));
            expect(circle.height, closeTo(density.leading, 0.01));
            expect(rect.center.dy, greaterThan(circle.center.dy));
            expect(rect.center.dy, lessThanOrEqualTo(circle.bottom + 0.01));
            expect(
              (rect.center - circle.center).distance,
              closeTo(circle.width / 2, 0.03),
              reason: 'badge center sits on the main circle circumference',
            );
            final halo = tester.widget<Container>(badge(id));
            expect(
              (halo.decoration! as BoxDecoration).color,
              Theme.of(tester.element(badge(id)))
                  .colorScheme
                  .surfaceContainerLowest,
            );
            // A badge painted outside the stack cannot receive a long press.
            // Fixed center means bottom badges can project below the orbit
            // square, but they remain within the padded card material.
            final card = tester.getRect(find.byType(NoteCard));
            expect(rect.top, greaterThanOrEqualTo(card.top));
            expect(rect.bottom, lessThanOrEqualTo(card.bottom));
            positions.add(rect.center.dx);
          }
          expect(positions, orderedEquals([...positions]..sort()));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('tag dots show at most three, even on legacy notes', (
    tester,
  ) async {
    for (var count = 1; count <= 4; count++) {
      await pump(
        tester,
        note(0, tags: [for (var i = 0; i < count; i++) tag(i)]),
      );
      final orb = tester.getRect(
        find.byKey(const ValueKey('note-leading-orbit')),
      );
      final shown = count > nexMaxTagsPerNote ? nexMaxTagsPerNote : count;
      final dots = [
        for (var i = 0; i < shown; i++)
          tester.getRect(find.byKey(ValueKey('note-tag-dot-$i'))),
      ];
      expect(find.byKey(ValueKey('note-tag-dot-$shown')), findsNothing);
      final circle = tester.getRect(
        find.byKey(const ValueKey('note-main-circle-paint')),
      );
      for (final dot in dots) {
        expect(dot.center.dy, lessThan(orb.center.dy));
        expect(
          (dot.center - circle.center).distance,
          closeTo(circle.width / 2, 0.03),
          reason: 'tag center must be precisely on the main circle rim',
        );
      }
      expect(
        dots.map((r) => r.center.dx).toList(),
        orderedEquals([...dots.map((r) => r.center.dx)]..sort()),
      );
    }
  });

  testWidgets('tags and statuses share the same circle circumference', (
    tester,
  ) async {
    for (final density in NexCardDensity.values) {
      for (final rtl in [false, true]) {
        final value = note(7, tags: [tag(0), tag(1), tag(2)]);
        await pump(tester, value, density: density, rtl: rtl);
        final circle = tester.getRect(
          find.byKey(const ValueKey('note-main-circle-paint')),
        );
        expect(circle.width, closeTo(density.leading, 0.03));
        expect(circle.height, closeTo(density.leading, 0.03));
        for (final id in ['attachment', 'urgent', 'reminder']) {
          final mark = tester.getRect(badge(id));
          expect(
            (mark.center - circle.center).distance,
            closeTo(circle.width / 2, 0.03),
          );
        }
        for (var i = 0; i < 3; i++) {
          final dot = tester.getRect(find.byKey(ValueKey('note-tag-dot-$i')));
          expect(
            (dot.center - circle.center).distance,
            closeTo(circle.width / 2, 0.03),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('adding statuses never moves the main circle', (tester) async {
    for (final density in NexCardDensity.values) {
      for (final rtl in [false, true]) {
        double? originalTop;
        for (final mask in [0, 1, 2, 4, 7]) {
          await pump(tester, note(mask), density: density, rtl: rtl);
          await tester.pumpAndSettle();
          final circle = tester.getRect(
            find.byKey(const ValueKey('note-main-circle-paint')),
          );
          originalTop ??= circle.top;
          expect(circle.top, closeTo(originalTop, 0.01));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('three coloured tag dots never overlap', (tester) async {
    for (final density in NexCardDensity.values) {
      await pump(
        tester,
        note(7, tags: [tag(0), tag(1), tag(2)]),
        density: density,
      );
      final dots = [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byKey(ValueKey('note-tag-dot-$i'))),
      ];
      for (var i = 1; i < dots.length; i++) {
        expect(dots[i - 1].right, lessThan(dots[i].left));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('marker backgrounds match selected and normal cards', (
    tester,
  ) async {
    for (final selected in <bool?>[null, false, true]) {
      await pump(
        tester,
        note(7, tags: [tag(0), tag(1), tag(2)]),
        selected: selected,
      );
      final cardColor = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('note-leading-orbit')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;
      for (var i = 0; i < 3; i++) {
        final dot = tester.widget<Container>(
          find.byKey(ValueKey('note-tag-dot-$i')),
        );
        expect((dot.decoration! as BoxDecoration).color, cardColor);
      }
      for (final id in ['attachment', 'urgent', 'reminder']) {
        final mark = tester.widget<Container>(badge(id));
        expect((mark.decoration! as BoxDecoration).color, cardColor);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('all note kinds and text scales share the collapsed height', (
    tester,
  ) async {
    for (final density in NexCardDensity.values) {
      double? height;
      for (final type in NoteType.values) {
        for (final mask in [0, 7]) {
          await pump(
            tester,
            note(
              mask,
              type: type,
              caption: type == NoteType.text ? 'Muted caption' : null,
            ),
            width: 220,
            scale: 1.9,
            density: density,
          );
          height ??= tester.getSize(find.byType(NoteCard)).height;
          expect(tester.getSize(find.byType(NoteCard)).height, height);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('reminder and attachment semantics stay accessible', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, note(7));
    expect(find.bySemanticsLabel('Full reminder schedule'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('3 more files')), findsOneWidget);
    await tester.longPress(find.byIcon(Icons.notifications_active_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Full reminder schedule'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('selection and ringing use the same circle and status badges', (
    tester,
  ) async {
    await pump(tester, note(7), ringing: true);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(badge('urgent'), findsOneWidget);
    await pump(tester, note(7), selected: true, ringing: true);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
    expect(badge('urgent'), findsOneWidget);
    expect(badge('reminder'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    await pump(tester, note(7), selected: false);
    expect(badge('attachment'), findsOneWidget);
  });

  testWidgets('caption remains muted and badges can disappear', (tester) async {
    await pump(tester, note(0, caption: 'Secondary caption'));
    final caption = tester.widget<NexTextSurface>(
      find.byKey(const ValueKey('note-card-caption')),
    );
    expect(
      caption.style!.color,
      Theme.of(tester.element(find.byType(NoteCard)))
          .colorScheme
          .onSurfaceVariant,
    );
    for (final id in ['reminder', 'attachment', 'urgent']) {
      expect(badge(id), findsNothing);
    }
  });
}
