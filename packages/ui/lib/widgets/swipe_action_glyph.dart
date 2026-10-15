part of 'swipeable_note_card.dart';

/// Each action moves its own parts as the finger reveals it. Only crossing
/// the existing commit point adds a single, finite confirmation beat.
class NexSwipeActionGlyph extends StatefulWidget {
  const NexSwipeActionGlyph({
    super.key,
    required this.action,
    required this.progress,
    required this.armed,
    this.color = Colors.white,
  });

  final NexSwipeAction action;
  final double progress;
  final bool armed;
  final Color color;

  @override
  State<NexSwipeActionGlyph> createState() => _NexSwipeActionGlyphState();
}

class _NexSwipeActionGlyphState extends State<NexSwipeActionGlyph>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: NexMotion.morph,
  );

  @override
  void didUpdateWidget(NexSwipeActionGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.value = 0;
    } else if (widget.action != oldWidget.action) {
      _beat.value = 0;
    } else if (widget.armed && !oldWidget.armed) {
      _beat.forward(from: 0);
    } else if (!widget.armed && oldWidget.armed) {
      _beat.animateBack(0, duration: NexMotion.fast, curve: NexMotion.curve);
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 26,
        child: AnimatedBuilder(
          animation: _beat,
          builder: (context, _) => CustomPaint(
            painter: _SwipeGlyphPainter(
              action: widget.action,
              progress: still ? 0 : widget.progress.clamp(0, 1),
              beat: still ? 0 : math.sin(_beat.value * math.pi),
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeGlyphPainter extends CustomPainter {
  const _SwipeGlyphPainter({
    required this.action,
    required this.progress,
    required this.beat,
    required this.color,
  });

  final NexSwipeAction action;
  final double progress;
  final double beat;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (action) {
      case NexSwipeAction.delete:
        canvas.drawPath(
          Path()
            ..moveTo(6, 9)
            ..lineTo(7, 21)
            ..lineTo(17, 21)
            ..lineTo(18, 9),
          ink,
        );
        canvas.drawLine(const Offset(10, 11), const Offset(10, 18), ink);
        canvas.drawLine(const Offset(14, 11), const Offset(14, 18), ink);
        // Hinge at the left corner: the lid, including its handle, opens.
        canvas.save();
        canvas.translate(5, 7 - beat);
        canvas.rotate(-0.48 * progress - 0.16 * beat);
        canvas.drawLine(Offset.zero, const Offset(14, 0), ink);
        canvas.drawPath(
          Path()
            ..moveTo(5, 0)
            ..lineTo(5, -2)
            ..lineTo(9, -2)
            ..lineTo(9, 0),
          ink,
        );
        canvas.restore();
      case NexSwipeAction.addTag:
        // The cut corner unfolds and the punched hole opens with the drag.
        final fold = 2 * (1 - progress);
        canvas.drawPath(
          Path()
            ..moveTo(3, 4)
            ..lineTo(11, 4)
            ..lineTo(21, 14)
            ..lineTo(14, 21)
            ..lineTo(3, 10)
            ..close(),
          ink,
        );
        canvas.drawCircle(
          const Offset(7.5, 8),
          1.1 + 0.55 * progress + 0.2 * beat,
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(11, 4)
            ..lineTo(11 - fold, 7 + fold)
            ..lineTo(15, 8),
          ink..color = color.withValues(alpha: 0.3 + 0.7 * progress),
        );
      case NexSwipeAction.pin:
        // The pin's head presses onto its stem; the contact ring settles.
        final down = 2.2 * progress + beat;
        canvas.drawLine(const Offset(12, 15), const Offset(12, 22), ink);
        canvas.save();
        canvas.translate(0, down);
        canvas.drawPath(
          Path()
            ..moveTo(8, 2)
            ..lineTo(16, 2)
            ..moveTo(9, 2)
            ..lineTo(9, 8)
            ..lineTo(6, 11)
            ..lineTo(6, 13)
            ..lineTo(18, 13)
            ..lineTo(18, 11)
            ..lineTo(15, 8)
            ..lineTo(15, 2),
          ink,
        );
        canvas.restore();
        if (beat > 0) {
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(12, 21),
              width: 7 + 3 * beat,
              height: 2,
            ),
            ink..color = color.withValues(alpha: beat * 0.5),
          );
        }
      case NexSwipeAction.remind:
        canvas.drawPath(
          Path()
            ..moveTo(5, 17)
            ..lineTo(7, 14)
            ..lineTo(7, 9)
            ..cubicTo(7, 2, 17, 2, 17, 9)
            ..lineTo(17, 14)
            ..lineTo(19, 17)
            ..close(),
          ink,
        );
        canvas.drawLine(const Offset(12, 2), const Offset(12, 3), ink);
        // The clapper swings inside the stationary bell.
        final swing = math.sin(progress * math.pi * 2) * 1.8 + beat;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(12 + swing, 18.5),
            width: 4,
            height: 4,
          ),
          0,
          math.pi,
          false,
          ink,
        );
        if (progress > 0.35) {
          ink.color = color.withValues(
            alpha: ((progress - 0.35) / 0.65).clamp(0, 1),
          );
          canvas.drawArc(
            const Rect.fromLTWH(3, 5, 18, 13),
            math.pi * 1.05,
            math.pi * 0.22,
            false,
            ink,
          );
          canvas.drawArc(
            const Rect.fromLTWH(3, 5, 18, 13),
            -math.pi * 0.27,
            math.pi * 0.22,
            false,
            ink,
          );
        }
      case NexSwipeAction.share:
        canvas.drawPath(
          Path()
            ..moveTo(4, 13)
            ..lineTo(4, 21)
            ..lineTo(20, 21)
            ..lineTo(20, 13),
          ink,
        );
        // The arrow rises out of the tray rather than moving the whole glyph.
        final top = 6 - 3 * progress - beat;
        canvas.drawPath(
          Path()
            ..moveTo(12, 16)
            ..lineTo(12, top)
            ..moveTo(8, top + 4)
            ..lineTo(12, top)
            ..lineTo(16, top + 4),
          ink,
        );
      case NexSwipeAction.ask:
        void sparkle(Offset center, double radius, double phase) {
          final growth = (progress * 1.8 - phase).clamp(0.0, 1.0);
          final r = radius * (0.65 + growth * 0.35 + beat * 0.15);
          final path = Path()
            ..moveTo(center.dx, center.dy - r)
            ..quadraticBezierTo(
              center.dx + r * 0.2,
              center.dy - r * 0.2,
              center.dx + r,
              center.dy,
            )
            ..quadraticBezierTo(
              center.dx + r * 0.2,
              center.dy + r * 0.2,
              center.dx,
              center.dy + r,
            )
            ..quadraticBezierTo(
              center.dx - r * 0.2,
              center.dy + r * 0.2,
              center.dx - r,
              center.dy,
            )
            ..quadraticBezierTo(
              center.dx - r * 0.2,
              center.dy - r * 0.2,
              center.dx,
              center.dy - r,
            )
            ..close();
          canvas.drawPath(
            path,
            ink..color = color.withValues(alpha: 0.55 + 0.45 * growth),
          );
        }
        sparkle(const Offset(10, 13), 7, 0);
        sparkle(const Offset(18, 5), 3, 0.45);
        sparkle(const Offset(20, 17), 2.5, 0.8);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwipeGlyphPainter old) =>
      old.action != action ||
      old.progress != progress ||
      old.beat != beat ||
      old.color != color;
}
