import 'package:flutter/material.dart';

/// A page with a sparkle beside it: "make something shorter out of this".
///
/// Not a Material glyph, because none of them says it. `summarize` is a page
/// with lines on it, which is what every other document icon in the app also
/// is — in a row of actions it read as "text", and nobody could tell from it
/// what the button would do. The sparkle is what the whole industry now uses
/// to mean "the machine will do this bit", and putting it on the page is the
/// difference between an icon that names a file type and one that names an
/// action.
///
/// Painted rather than composed from two glyphs so the sparkle can cut into
/// the page's outline instead of sitting on top of it. Two overlapping icons
/// leave a tangle of crossing strokes at small sizes, which is exactly the
/// size this is used at.
///
/// Takes its colour and size from the ambient [IconTheme], the same as
/// [Icon], so it drops into a row of icons without being told anything.
class NexSummariseIcon extends StatelessWidget {
  const NexSummariseIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final paint =
        color ??
        theme.color ??
        Theme.of(context).colorScheme.onSurface.withValues(
          alpha: theme.opacity ?? 1,
        );
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(painter: _SummarisePainter(paint)),
    );
  }
}

class _SummarisePainter extends CustomPainter {
  const _SummarisePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on Material's own 24x24 grid and scaled, so the stroke weight and
    // the proportions match the glyphs it sits next to at any size.
    final scale = size.shortestSide / 24;
    canvas.scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The page, open at the bottom right where the sparkle comes through.
    // Drawn as one path from the fold so the corner reads as folded paper
    // rather than as a clipped rectangle.
    final page = Path()
      ..moveTo(12.6, 2.6)
      ..lineTo(5.4, 2.6)
      ..quadraticBezierTo(4.2, 2.6, 4.2, 3.8)
      ..lineTo(4.2, 17.8)
      ..quadraticBezierTo(4.2, 19, 5.4, 19)
      ..lineTo(10.4, 19)
      // Stops here. The sparkle occupies the corner, and an outline running
      // behind it would cross its strokes twice.
      ..moveTo(15.8, 6.2)
      ..lineTo(15.8, 11.2)
      // The fold: the cut corner, then the flap it leaves behind.
      ..moveTo(12.6, 2.6)
      ..lineTo(15.8, 5.8)
      ..moveTo(12.6, 2.6)
      ..lineTo(12.6, 5.8)
      ..lineTo(15.8, 5.8);
    canvas.drawPath(page, stroke);

    // Three lines of writing, the last one short — a paragraph, not a form.
    for (final (y, end) in const [(8.6, 13.2), (11.4, 13.2), (14.2, 10.6)]) {
      canvas.drawLine(Offset(7.0, y), Offset(end, y), stroke);
    }

    _sparkle(canvas, stroke, const Offset(16.6, 16.4), 5.2);
    _sparkle(canvas, stroke, const Offset(21.0, 10.6), 2.6);
  }

  /// A four-pointed star with the sides pulled in towards the middle, which
  /// is what makes it read as a glint rather than as a diamond.
  void _sparkle(Canvas canvas, Paint stroke, Offset centre, double radius) {
    final waist = radius * 0.22;
    final path = Path()
      ..moveTo(centre.dx, centre.dy - radius)
      ..quadraticBezierTo(
        centre.dx + waist,
        centre.dy - waist,
        centre.dx + radius,
        centre.dy,
      )
      ..quadraticBezierTo(
        centre.dx + waist,
        centre.dy + waist,
        centre.dx,
        centre.dy + radius,
      )
      ..quadraticBezierTo(
        centre.dx - waist,
        centre.dy + waist,
        centre.dx - radius,
        centre.dy,
      )
      ..quadraticBezierTo(
        centre.dx - waist,
        centre.dy - waist,
        centre.dx,
        centre.dy - radius,
      )
      ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_SummarisePainter old) => old.color != color;
}
