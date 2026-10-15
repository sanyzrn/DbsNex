part of 'swipeable_note_card.dart';

/// Keeps the design system independent of the app's bundled animation player.
typedef NexSwipeGlyphBuilder =
    Widget Function(
      BuildContext context,
      NexSwipeAction action,
      double progress,
      bool armed,
      Color color,
    );

class NexSwipeGlyphTheme extends InheritedWidget {
  const NexSwipeGlyphTheme({
    super.key,
    required this.builder,
    required super.child,
  });
  final NexSwipeGlyphBuilder builder;

  @override
  bool updateShouldNotify(NexSwipeGlyphTheme oldWidget) =>
      builder != oldWidget.builder;
}

/// The application supplies ready-made animation assets; other consumers have
/// a standard Material glyph. No custom icon geometry lives in the swipe card.
class NexSwipeActionGlyph extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = context
        .dependOnInheritedWidgetOfExactType<NexSwipeGlyphTheme>();
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 28,
        child:
            theme?.builder(
              context,
              action,
              still ? 0 : progress.clamp(0, 1),
              !still && armed,
              color,
            ) ??
            Icon(
              switch (action) {
                NexSwipeAction.delete => Icons.delete_outline,
                NexSwipeAction.addTag => Icons.sell_outlined,
                NexSwipeAction.pin => Icons.push_pin_outlined,
                NexSwipeAction.remind => Icons.notifications_outlined,
                NexSwipeAction.share => Icons.ios_share,
                NexSwipeAction.ask => Icons.auto_awesome_outlined,
              },
              color: color,
              size: 24,
            ),
      ),
    );
  }
}
