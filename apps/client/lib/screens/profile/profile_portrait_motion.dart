part of 'profile_portrait.dart';

/// One 0→1 clock for the whole portrait's arrival. Every section reads its own
/// slice of it ([_Staged]), every number counts up on it ([_CountUp]), every
/// chart draws on it, so the card assembles itself in order instead of
/// appearing all at once.
class _Entrance extends InheritedWidget {
  const _Entrance({required this.animation, required super.child});

  final Animation<double> animation;

  /// Finished, for anything shown without the card around it.
  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Entrance>()?.animation ??
      kAlwaysCompleteAnimation;

  @override
  bool updateShouldNotify(_Entrance old) => animation != old.animation;
}

/// How far along section [slot] is when the whole entrance is at [t]: each one
/// starts a beat after the one above it and takes [span] of the whole.
double _slice(double t, int slot, {double span = 0.3}) {
  final start = slot * 0.045;
  return NexMotion.curve.transform(((t - start) / span).clamp(0.0, 1.0));
}

/// Fades a section in while it rises a few pixels into place.
class _Staged extends StatelessWidget {
  const _Staged({required this.slot, required this.child});

  final int slot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final entrance = _Entrance.of(context);
    return AnimatedBuilder(
      animation: entrance,
      child: child,
      builder: (context, child) {
        final p = _slice(entrance.value, slot);
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - p)),
            child: child,
          ),
        );
      },
    );
  }
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
