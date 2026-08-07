import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// A placeholder for something that is on its way.
///
/// The app had no loading affordance anywhere: every async surface — the
/// timeline, a filter being applied, search, the tag list, the storage figure —
/// went from stale content straight to new content with nothing in between
/// saying work was in flight. The worst case was the timeline, which rendered
/// its full-screen onboarding copy on the first frame of every cold launch
/// because "not loaded yet" and "empty" were the same value.
///
/// The shimmer stops when animations are off. `MediaQuery.disableAnimations`
/// already carries the in-app reduce-motion preference (see `app.dart`), so
/// this needs no preference of its own.
class NexSkeleton extends StatefulWidget {
  const NexSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = NexRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<NexSkeleton> createState() => _NexSkeletonState();
}

class _NexSkeletonState extends State<NexSkeleton>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily. A `late final` here is only initialised
  // on first touch, and a skeleton that is built and removed inside one frame —
  // which is exactly what a fast timeline load does to it — reaches `dispose`
  // first, so the ticker was being created against an element that had already
  // been deactivated.
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not merely hidden when animations are off — stopped. A repeating
    // controller left running would go on requesting a frame every 16ms
    // forever, which is precisely the cost reduce-motion exists to avoid, and
    // it never settles.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _shimmer.isAnimating) {
      _shimmer.stop();
    } else if (!still && !_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final box = SizedBox(width: widget.width, height: widget.height);

    if (MediaQuery.disableAnimationsOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: box,
      );
    }

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        // A band travelling left to right, wider than the box so the highlight
        // enters and leaves rather than appearing in place.
        final t = _shimmer.value * 2 - 0.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: [
                base,
                Color.alphaBlend(scheme.surface.withValues(alpha: 0.55), base),
                base,
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          child: box,
        );
      },
    );
  }
}

/// A timeline card that has not arrived yet.
///
/// Built to the real card's dimensions — [nexCardHeight] inside
/// [nexCardInsets], with the leading disc where the leading disc goes — so the
/// list does not reflow when the notes land on top of it.
class NexCardSkeleton extends StatelessWidget {
  const NexCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: nexCardInsets,
      child: SizedBox(
        height: nexCardHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.cardInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NexSkeleton(
                  width: nexCardLeadingSize,
                  height: nexCardLeadingSize,
                  // Matches the leading icon box it stands in for — see
                  // NexRadius.cardLeading.
                  radius: NexRadius.cardLeading,
                ),
                const SizedBox(width: NexSpacing.contentGap),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sized to fit nexCardLeadingSize's own height, same as
                      // the real preview-plus-timestamp column beside it —
                      // shrinking the icon box shrinks the room this has too.
                      NexSkeleton(height: 14),
                      SizedBox(height: NexSpacing.xs),
                      // Short, the way a second line of a preview usually is.
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 0.6,
                        child: NexSkeleton(height: 14),
                      ),
                      Spacer(),
                      NexSkeleton(width: 72, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
