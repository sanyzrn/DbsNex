part of 'swipeable_note_card.dart';

/// A familiar Material icon with one short acknowledgement as it is revealed
/// and when the full-swipe threshold changes. Motion completes even when the
/// finger pauses; no playback frame is tied to drag distance.
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
  late final _pulse = AnimationController(
    vsync: this,
    duration: NexMotion.standard,
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.14,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.14,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]).animate(_pulse);

  bool get _visible => widget.progress >= 0.12;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.reset();
    } else if (_visible && !_pulse.isAnimating) {
      _pulse.forward();
    }
  }

  @override
  void didUpdateWidget(NexSwipeActionGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaQuery.disableAnimationsOf(context)) return;
    if ((!(oldWidget.progress >= 0.12) && _visible) ||
        (oldWidget.armed != widget.armed && _visible)) {
      _pulse.forward(from: 0);
    } else if (!_visible) {
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 28,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, still ? 0 : -(_scale.value - 1) * 14),
            child: Transform.scale(
              scale: still ? 1 : _scale.value,
              child: child,
            ),
          ),
          child: Icon(
            switch (widget.action) {
              NexSwipeAction.delete => Icons.delete_outline,
              NexSwipeAction.addTag => Icons.sell_outlined,
              NexSwipeAction.pin => Icons.push_pin_outlined,
              NexSwipeAction.remind => Icons.notifications_outlined,
              NexSwipeAction.share => Icons.ios_share,
              NexSwipeAction.ask => Icons.auto_awesome_outlined,
            },
            color: widget.color,
            size: 24,
          ),
        ),
      ),
    );
  }
}
