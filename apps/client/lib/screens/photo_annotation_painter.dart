part of 'photo_annotate_screen.dart';

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, {super.repaint});

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final points = stroke.points;
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawCircle(
          points.first,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      // Through the midpoints, with each sampled point as the curve's
      // control: a line that bends where the finger did, rather than a chain
      // of straight segments that shows its corners on a fast stroke.
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length - 1; i++) {
        final mid = (points[i] + points[i + 1]) / 2;
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  // The strokes grow in place as a finger moves, and [repaint] says when;
  // a new list means marks were added or taken away.
  @override
  bool shouldRepaint(_StrokePainter oldDelegate) => true;
}
