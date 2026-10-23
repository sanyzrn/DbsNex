part of 'profile_portrait.dart';

/// The 0→1 clock of the section being drawn, handed down by [_Staged]: every
/// number counts up on it and every chart draws on it. Each section has its
/// own, started when that section is scrolled into view, so what is further
/// down the card arrives when the reader gets to it, not all at once on entry.
class _Entrance extends InheritedWidget {
  const _Entrance({required this.animation, required super.child});

  final Animation<double> animation;

  /// Finished, for anything shown without a section around it.
  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Entrance>()?.animation ??
      kAlwaysCompleteAnimation;

  @override
  bool updateShouldNotify(_Entrance old) => animation != old.animation;
}

/// How far along a part of a section is when the section's clock is at [t]. A
/// small [slot] (0–4) staggers parts inside one section; larger ones are the
/// same as 4, because they used to place sections on one shared clock.
double _slice(double t, int slot, {double span = 0.5}) {
  final start = slot.clamp(0, 4) * 0.06;
  return NexMotion.curve.transform(((t - start) / span).clamp(0.0, 1.0));
}

/// Fades a section in while it rises a few pixels, when it comes into view.
///
/// Watches the scroll position it sits in and starts on its own clock the
/// first time its top is within the window (anything already above the window
/// counts, so a fast scroll past it still lands it settled). Without a
/// scrollable around it, or with reduced motion, it is simply there.
class _Staged extends StatefulWidget {
  const _Staged({required this.slot, required this.child});

  final int slot;
  final Widget child;

  @override
  State<_Staged> createState() => _StagedState();
}

class _StagedState extends State<_Staged> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _clock,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );
  late final Animation<Offset> _rise = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _clock, curve: NexMotion.curve));
  ScrollPosition? _watching;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clock.value > 0 || _watching != null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
      return;
    }
    // After this frame's layout, so the position is known.
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrive());
  }

  void _arrive() {
    if (!mounted || _clock.value > 0) return;
    if (_seen()) {
      unawaited(_clock.forward());
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      _clock.value = 1;
      return;
    }
    _watching = position..addListener(_maybeArrive);
  }

  void _maybeArrive() {
    if (!mounted || !_seen()) return;
    _watching?.removeListener(_maybeArrive);
    _watching = null;
    unawaited(_clock.forward());
  }

  /// Whether the section's top is inside the window, with a little margin so
  /// it starts as it comes up rather than when it is already all there.
  bool _seen() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    return top < MediaQuery.sizeOf(context).height * 0.92;
  }

  @override
  void dispose() {
    _watching?.removeListener(_maybeArrive);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Entrance(
    animation: _clock,
    // Composited, not rebuilt: the section's own widgets do not change while
    // it fades, only the layer they are drawn into.
    child: RepaintBoundary(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _rise, child: widget.child),
      ),
    ),
  );
}

/// A number that counts up to [value] as its section arrives.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.slot,
    required this.style,
    this.suffix = '',
    this.persian = false,
  });

  final int value;
  final int slot;
  final TextStyle? style;
  final String suffix;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final entrance = _Entrance.of(context);
    return AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final shown = (value * _slice(entrance.value, slot, span: 0.4)).round();
        return Text(
          nexDigits('$shown$suffix', persian: persian),
          textDirection: TextDirection.ltr,
          style: style,
        );
      },
    );
  }
}
