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
/// selected runs. Only their vertical bounds should agree.
List<Rect> nexLevelSelectionRects(List<Rect> source) {
  final sorted = source.where((r) => !r.isEmpty).toList()
    ..sort((a, b) => a.top.compareTo(b.top));
  final result = <Rect>[];
  final row = <Rect>[];
  Rect? bounds;
  void flush() {
    if (bounds == null) return;
    for (final rect in row) {
      result.add(
        Rect.fromLTRB(rect.left, bounds.top, rect.right, bounds.bottom),
      );
    }
    row.clear();
  }

  for (final rect in sorted) {
    // Runs share a row if their vertical centers overlap. Neighboring lines
    // and headings retain their own height and spacing.
    if (bounds != null &&
        (rect.center.dy >= bounds.bottom || rect.bottom <= bounds.center.dy)) {
      flush();
      bounds = null;
    }
    row.add(rect);
    bounds = bounds == null ? rect : bounds.expandToInclude(rect);
  }
  flush();
  return result;
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(this.selection, this.color) : super(repaint: selection);

  final ValueListenable<SelectionGeometry> selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final rect in nexLevelSelectionRects(selection.value.selectionRects)) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.selection != selection || old.color != color;
}
