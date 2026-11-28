import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show SelectionGeometry;

/// Paints a level highlight across font runs on the same visual row.
/// Selection, handles, hit testing and copied content remain Flutter's.
class NexSelectionHighlight extends StatefulWidget {
  const NexSelectionHighlight({super.key, required this.child});

  final Widget child;

  @override
  State<NexSelectionHighlight> createState() => _NexSelectionHighlightState();
}

class _NexSelectionHighlightState extends State<NexSelectionHighlight> {
  final _selection = StaticSelectionContainerDelegate();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        DefaultSelectionStyle.of(context).selectionColor ??
        DefaultSelectionStyle.defaultColor;
    return DefaultSelectionStyle.merge(
      selectionColor: Colors.transparent,
      child: SelectionContainer(
        delegate: _selection,
        child: CustomPaint(
          painter: _HighlightPainter(_selection, color),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Keep horizontal gaps: a bidi selection can have unselected text between
/// selected runs. Vertical bounds are unified per visual row, overlapping
/// horizontal runs within a row are merged, and adjacent rows are clamped so
/// semi-transparent highlights never overlap and double-paint.
List<Rect> nexLevelSelectionRects(List<Rect> source) {
  final sorted = source.where((r) => !r.isEmpty).toList()
    ..sort((a, b) => a.top.compareTo(b.top));
  final rows = <({double top, double bottom, List<Rect> spans})>[];
  final row = <Rect>[];
  Rect? bounds;

  void flush() {
    final rowBounds = bounds;
    if (rowBounds == null) return;
    row.sort((a, b) => a.left.compareTo(b.left));
    final merged = <Rect>[];
    for (final rect in row) {
      if (merged.isNotEmpty && rect.left < merged.last.right) {
        final last = merged.removeLast();
        merged.add(
          Rect.fromLTRB(
            last.left,
            rowBounds.top,
            rect.right > last.right ? rect.right : last.right,
            rowBounds.bottom,
          ),
        );
      } else {
        merged.add(
          Rect.fromLTRB(rect.left, rowBounds.top, rect.right, rowBounds.bottom),
        );
      }
    }
    rows.add((top: rowBounds.top, bottom: rowBounds.bottom, spans: merged));
    row.clear();
  }

  for (final rect in sorted) {
    // Runs share a row if their vertical centers overlap. Neighboring lines
    // and headings retain their own height and spacing.
    final rowBounds = bounds;
    if (rowBounds != null &&
        (rect.center.dy >= rowBounds.bottom ||
            rect.bottom <= rowBounds.center.dy)) {
      flush();
      bounds = null;
    }
    row.add(rect);
    bounds = bounds?.expandToInclude(rect) ?? rect;
  }
  flush();

  // Clamp adjacent visual rows so tall glyphs or line-height multipliers
  // cannot cause consecutive lines to overlap and double-blend alpha.
  final result = <Rect>[];
  for (var i = 0; i < rows.length; i++) {
    var top = rows[i].top;
    var bottom = rows[i].bottom;
    if (i > 0 && top < rows[i - 1].bottom) {
      top = (rows[i - 1].bottom + top) / 2;
    }
    if (i + 1 < rows.length && bottom > rows[i + 1].top) {
      bottom = (bottom + rows[i + 1].top) / 2;
    }
    if (bottom <= top) continue;
    for (final span in rows[i].spans) {
      result.add(Rect.fromLTRB(span.left, top, span.right, bottom));
    }
  }
  return result;
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(this.selection, this.color) : super(repaint: selection);

  final ValueListenable<SelectionGeometry> selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rects = nexLevelSelectionRects(selection.value.selectionRects);
    if (rects.isEmpty) return;
    final path = Path();
    for (final rect in rects) {
      path.addRect(rect);
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.selection != selection || old.color != color;
}
