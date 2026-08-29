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
/// Built to the real card's dimensions — [nexCardHeightFor] inside
/// [nexCardInsets], with the leading disc where the leading disc goes — so the
/// list does not reflow when the notes land on top of it. The height has to go
/// through the same context-aware helper the card does, or a reader with the
/// text turned up gets a jump the moment the real cards arrive.
class NexCardSkeleton extends StatelessWidget {
  const NexCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: nexCardInsets,
      child: SizedBox(
        height: nexCardHeightFor(context),
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

/// A list of placeholder rows, for a screen whose first read has not returned.
///
/// [NexCardSkeleton] is the timeline's shape and the wrong one here: the tag
/// manager, the trash and the backup list are `ListTile` rows, so standing in
/// for them with cards would reflow the whole screen the moment the real rows
/// arrived — which is the jump a skeleton exists to prevent.
///
/// This is not decoration. The screens that use it opened by *claiming* to be
/// empty and then filling in, so a slow read read as data loss on the three
/// screens that manage data. A placeholder says "not yet" where those said
/// "there is nothing".
class NexLoadingList extends StatelessWidget {
  const NexLoadingList({super.key, this.rows = 5});

  /// Enough to look like a list rather than an accident, without implying a
  /// count — the real one is not known yet.
  final int rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
    // Not scrollable: there is nothing to reach, and a placeholder that moves
    // under the finger invites pulling at something that cannot respond.
    physics: const NeverScrollableScrollPhysics(),
    itemCount: rows,
    separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (_, __) => const _TileSkeleton(),
  );
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) => const SizedBox(
    // The `minTileHeight` every one of these lists gives its real rows.
    height: 56,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: NexSpacing.md),
      child: Row(
        children: [
          NexSkeleton(width: 24, height: 24, radius: 12),
          SizedBox(width: NexSpacing.contentGap),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 0.45,
                  child: NexSkeleton(height: 14),
                ),
                SizedBox(height: NexSpacing.xs),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 0.25,
                  child: NexSkeleton(height: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
