import 'dart:ui' as ui;
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
                child: RepaintBoundary(
                  key: const ValueKey('pixels'),
                  child: NoteCard(
                    note: value,
                    strings: strings,
                    selected: selected,
                    onTap: () {},
                    previewOverride: preview,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Finder halo(String id) => find.byKey(ValueKey('note-status-halo-$id'));
  for (final rtl in [false, true]) {
    for (final density in NexCardDensity.values) {
      testWidgets(
        '$rtl $density: one, two and three lines are vertically centred',
        (tester) async {
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
        },
      );
      testWidgets('$rtl $density: marks preserve full-width text and height', (
        tester,
      ) async {
        Size? size;
        List<Rect>? boxes;
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
          final actual = p
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: value.content!.length,
                ),
              )
              .map((b) => b.toRect())
              .toList();
          size ??= p.size;
          boxes ??= actual;
          height ??= tester.getSize(find.byType(NoteCard)).height;
          expect(p.size, size);
          expect(actual, boxes);
          expect(actual.map((b) => b.top).toSet(), hasLength(density.lines));
          expect(tester.getSize(find.byType(NoteCard)).height, height);
          expect(find.text('2d'), findsNothing);
          expect(find.text('+3'), findsNothing);
          final ids = [
            if (mask & 1 != 0) 'reminder',
            if (mask & 2 != 0) 'attachment',
            if (mask & 4 != 0) 'urgent',
          ];
          final area = tester.getRect(
            find.byKey(const ValueKey('note-card-preview')),
          );
          Rect? previous;
          for (final id in ids) {
            final rect = tester.getRect(halo(id));
            expect(rect.size, const Size(18, 22));
            final surface = tester.getRect(
              find
                  .descendant(
                    of: find.byType(NoteCard),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(rect.bottom, closeTo(surface.bottom - 4, .01));
            if (previous == null) {
              expect(
                rtl ? rect.right : rect.left,
                closeTo(rtl ? area.right : area.left, .01),
              );
            } else {
              expect(
                rtl ? previous.left - rect.right : rect.left - previous.right,
                closeTo(0, .01),
              );
            }
            previous = rect;
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets(
    'all note types and captions retain the same envelope at larger text',
    (tester) async {
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
    },
  );
  testWidgets('hidden labels retain reminder semantics and attachment data', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final value = note(7);
    await pump(tester, value);
    expect(find.text('2d'), findsNothing);
    expect(find.text('+3'), findsNothing);
    expect(find.bySemanticsLabel('Full reminder schedule'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('3 more files')), findsOneWidget);
    expect(value.dueAt, at);
    expect(value.attachmentCount, 3);
    await tester.longPress(find.byIcon(Icons.notifications_active_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Full reminder schedule'), findsOneWidget);
    handle.dispose();
  });
  for (final dark in [false, true]) {
    testWidgets(
      '$dark: tiny radial halos follow pressed/selected card surface',
      (tester) async {
        for (final selected in [false, true]) {
          await pump(
            tester,
            note(7),
            dark: dark,
            selected: selected,
            preview: const SizedBox.expand(
              child: ColoredBox(color: Color(0xFFFF00FF)),
            ),
          );
          final h = halo('urgent');
          expect(find.byKey(const ValueKey('note-status-fill')), findsNothing);
          expect(find.byType(ShaderMask), findsNWidgets(3));
          for (final mask in tester.widgetList<ShaderMask>(
            find.byType(ShaderMask),
          )) {
            expect(mask.blendMode, BlendMode.dstOut);
          }
          final rect = tester.getRect(h);
          Future<int> pixel() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('pixels')),
            );
            final local =
                Offset(rect.center.dx, rect.center.dy + 9) -
                boundary.localToGlobal(Offset.zero);
            final im = await tester.runAsync(
              () => boundary.toImage(pixelRatio: 1),
            );
            final bytes = await tester.runAsync(
              () => im!.toByteData(format: ui.ImageByteFormat.rawRgba),
            );
            final offset =
                (local.dy.floor() * im!.width + local.dx.floor()) * 4;
            final result =
                bytes!.getUint8(offset) << 16 |
                bytes.getUint8(offset + 1) << 8 |
                bytes.getUint8(offset + 2);
            im.dispose();
            return result;
          }

          final before = await pixel();
          final finger = await tester.startGesture(
            tester.getCenter(find.byType(NoteCard)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 220));
          expect(await pixel(), isNot(before));
          await finger.up();
          await tester.pumpAndSettle();
          expect(await pixel(), before);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('caption stays grey and the icon group can disappear entirely', (
    tester,
  ) async {
    await pump(tester, note(0, caption: 'Secondary caption'));
    final caption = tester.widget<NexTextSurface>(
      find.byKey(const ValueKey('note-card-caption')),
    );
    expect(
      caption.style!.color,
      Theme.of(
        tester.element(find.byType(NoteCard)),
      ).colorScheme.onSurfaceVariant,
    );
    expect(halo('reminder'), findsNothing);
    expect(halo('attachment'), findsNothing);
    expect(halo('urgent'), findsNothing);
  });
}
