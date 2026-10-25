part of 'note_card.dart';

/// The leading square of a note whose reminder has rung and not been looked
/// at (2.3.0): a bell in place of the note's type, swinging now and then, with
/// a soft ring spreading from it as it swings — until the card is opened.
///
/// Swings in short bursts with a rest between, the way a bell actually rings,
/// rather than wobbling non-stop: one card asking for attention should not
/// make a whole screen shimmer. Still with reduced motion, and paused with
/// the ticker when the card is off screen.
class _RingingBell extends StatefulWidget {
  const _RingingBell();

  @override
  State<_RingingBell> createState() => _RingingBellState();
}

class _RingingBellState extends State<_RingingBell>
    with SingleTickerProviderStateMixin {
  /// One swing and its rest.
  static const _cycle = Duration(milliseconds: 2200);

  /// The part of [_cycle] spent swinging.
  static const _swing = 0.38;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.stop();
      _clock.value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = NexCardDensity.of(context).leading;
    final plain = MediaQuery.highContrastOf(context);
    final fill = plain ? scheme.surfaceContainerHighest : scheme.primary;
    final ink = plain ? scheme.onSurface : scheme.onPrimary;
    return SizedBox.square(
      dimension: side,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value;
          final swinging = t < _swing;
          final local = swinging ? t / _swing : 0.0;
          // A damped swing: three to-and-fros, each smaller than the last.
          final angle = swinging
              ? math.sin(local * math.pi * 6) * 0.38 * (1 - local)
              : 0.0;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (swinging && !plain)
                // The sound, drawn: a ring leaving the square as it swings.
                Container(
                  width: side * (1 + 0.32 * local),
                  height: side * (1 + 0.32 * local),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      NexRadius.cardLeading * (1 + 0.32 * local),
                    ),
                    border: Border.all(
                      color: scheme.primary.withValues(
                        alpha: 0.5 * (1 - local),
                      ),
                      width: 2,
                    ),
                  ),
                ),
              Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(NexRadius.cardLeading),
                ),
                child: Transform.rotate(
                  angle: angle,
                  // From the top, where a bell hangs.
                  alignment: const Alignment(0, -0.6),
                  child: Icon(Icons.notifications_active_rounded, color: ink),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
