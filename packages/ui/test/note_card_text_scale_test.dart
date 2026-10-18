import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// The card grows with the text size — [nexCardHeightFor] exists for that, and
/// its own comment says why: "the alternative is a fixed box clipping the text
/// of whoever turned the size up."
///
/// The rows *inside* it did not. A checklist item and a link's two lines were
/// each `SizedBox(height: 24)`, which is one bodyLarge line at scale 1.0 and
/// nothing like one at 1.9 — so the card got taller while the text inside it
/// stayed squeezed into a box built for the default size. The app's own
/// UI-size setting composes with the system's accessibility curve, and its own
/// "Larger" step is 1.3, so this is reachable from the settings screen without
/// touching Android's.
///
/// Measured as the distance between one row and the next, deliberately.
/// Asserting "no exception" would have passed before the fix as well as after
/// it: a `Text` inside a too-short box is constrained by it rather than
/// reporting an overflow, so the failure is silent — clipped glyphs and rows
/// closer together than the text in them is tall, with nothing thrown.
void main() {
  final now = DateTime.utc(2026, 7, 28);

  const firstItem = 'call the dentist back about the appointment';
  const secondItem = 'buy bread';

  Note checklist() => Note(
    id: 'n-checklist',
    type: NoteType.checklist,
    content: '- [ ] $firstItem\n- [ ] $secondItem',
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  Future<void> pumpAt(WidgetTester tester, Note note, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(width: 400, child: NoteCard(note: note)),
          ),
        ),
      ),
    );
  }

  for (final scale in <double>[1.0, 1.3, 1.9, 3.2]) {
    testWidgets('checklist rows are one scaled line apart at $scale', (
      tester,
    ) async {
      // Tall enough that the card at 1.9 is not fighting the surface.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpAt(tester, checklist(), scale);

      final first = tester.getTopLeft(find.text(firstItem));
      final second = tester.getTopLeft(find.text(secondItem));
      final spacing = second.dy - first.dy;

      // The row height the card's own arithmetic reserves. At 1.0 this is 24
      // and the literal was right; past that the literal is the bug.
      final expected = nexCardPreviewLineHeightFor(
        tester.element(find.byType(NoteCard)),
      );
      expect(
        spacing,
        moreOrLessEquals(expected, epsilon: 0.5),
        reason:
            'two items sat $spacing apart with a line ${expected.toStringAsFixed(1)} tall',
      );
    });
  }

  testWidgets('the reserved row and the card grow together', (tester) async {
    // The two numbers that drifted apart: `nexCardHeightFor` scaled and the
    // rows inside it did not, so the height the card claimed stopped
    // describing what it drew.
    late double rowHeight;
    late double cardHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.9)),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                rowHeight = nexCardPreviewLineHeightFor(context);
                cardHeight = nexCardHeightFor(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(rowHeight, greaterThan(24.0), reason: 'scaled, not the literal');
    // Two preview lines are what the card reserves room for, so the rows it
    // draws have to fit inside the height it claims.
    expect(rowHeight * nexCardPreviewLines, lessThanOrEqualTo(cardHeight));
  });

  // 2.1.7: under a non-linear scaler the 14-point compact preview grew more
  // than the 20-point row reserved for it, and with a reminder below — where
  // the preview sits in a box of exactly two rows — the second line's bottom
  // was cut off. The box is now never shorter than the text it holds.
  testWidgets('compact two-line preview above a reminder is not clipped '
      'under non-linear scaling', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final note = Note(
      id: 'n-due',
      type: NoteType.text,
      content:
          'اضافه کاری غرفه جدید از لحظه خروج تا ساعت نوزده و سی\n'
          'اضافه کاری غرفه قبل از لحظه خروج تا ساعت هجده',
      createdAt: now,
      updatedAt: now,
      dueAt: now.add(const Duration(hours: 16)),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: _NonLinearScaler()),
          child: Scaffold(
            body: NexCardDensityScope(
              density: NexCardDensity.compact,
              child: SizedBox(
                width: 400,
                child: NoteCard(note: note, showDue: true),
              ),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains('غرفه'));
    final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    expect(paragraph.size.height, greaterThanOrEqualTo(needed - 0.01));
    expect(tester.takeException(), isNull);
  });
}

/// Small sizes grow more than large ones, the way Android's non-linear font
/// scaling does from Android 14.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();
  @override
  double scale(double fontSize) => fontSize + 4.2;
  @override
  double get textScaleFactor => scale(14) / 14;
}
