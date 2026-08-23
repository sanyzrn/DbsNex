import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// One stop on the tour: a real widget on screen, and what to say about it.
///
/// [key] is attached to the widget itself, which is what makes this point at
/// the thing rather than at a drawing of it — a highlight positioned from a
/// hardcoded rectangle is wrong the moment a phone is a different size, and
/// this app already renders at four text scales.
class TourStop {
  const TourStop({
    required this.key,
    required this.title,
    required this.body,
    this.radius = NexRadius.lg,
  });

  final GlobalKey key;
  final String title;
  final String body;

  /// The corner radius of the hole cut for this stop. The capture button is a
  /// circle; the search field is a capsule; a bare rectangle around either
  /// looks like a mistake.
  final double radius;
}

/// The short walk-through shown once, the first time the timeline opens.
///
/// Deliberately not part of onboarding. Onboarding asks four questions before
/// anyone has seen the app, and a tour there would be pointing at a screen
/// that is not on screen yet. This runs on the timeline itself, over the real
/// controls, which is the only moment "hold this button" means anything.
///
/// Shown exactly once and skippable from the first step. A tour nobody can
/// leave is worse than no tour, and one that comes back is a bug people
/// report as the app being broken.
class FirstRunTour extends StatefulWidget {
  const FirstRunTour({
    super.key,
    required this.stops,
    required this.onFinished,
  });

  final List<TourStop> stops;

  /// Called once, whether the tour was finished or skipped. Both mean the
  /// same thing to the preference behind it: do not show this again.
  final VoidCallback onFinished;

  @override
  State<FirstRunTour> createState() => _FirstRunTourState();
}

class _FirstRunTourState extends State<FirstRunTour> {
  int _index = 0;

  /// Where the stop's widget actually is, in the overlay's coordinates.
  ///
  /// Null when the widget is not laid out — a stop whose control is off
  /// screen or absent, which is a real case: the assistant's controls are not
  /// built at all without a provider. A stop with no rectangle is skipped
  /// rather than pointed at nothing.
  Rect? _rectFor(TourStop stop) {
    final context = stop.key.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  void _advance() {
    for (var next = _index + 1; next < widget.stops.length; next++) {
      if (_rectFor(widget.stops[next]) != null) {
        setState(() => _index = next);
        nexTick();
        return;
      }
    }
    _finish();
  }

  void _finish() {
    nexBump();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final stop = widget.stops[_index];
    final target = _rectFor(stop);
    if (target == null) {
      // Laid out after this frame, or gone. Either way there is nothing to
      // point at yet, so paint nothing rather than a hole in the wrong place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    final hole = target.inflate(NexSpacing.sm);
    final isLast = _index == widget.stops.length - 1;
    // Above the hole when the hole is in the lower half, below it otherwise —
    // the caption must never land on top of the thing it is describing.
    final captionAbove = hole.center.dy > media.size.height / 2;

    return Semantics(
      container: true,
      child: Stack(
        children: [
          // The scrim, minus the hole. Tapping it advances, which is what
          // people try first on anything that looks like this.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _advance,
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  radius: stop.radius,
                  color: theme.colorScheme.scrim.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          // A ring around the hole, so the cut-out reads as deliberate rather
          // than as the scrim having failed to paint.
          Positioned.fromRect(
            rect: hole,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(stop.radius),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: NexSpacing.md,
            right: NexSpacing.md,
            top: captionAbove ? null : hole.bottom + NexSpacing.md,
            bottom: captionAbove
                ? media.size.height - hole.top + NexSpacing.md
                : null,
            child: _Caption(
              title: stop.title,
              body: stop.body,
              step: _index + 1,
              total: widget.stops.length,
              nextLabel: isLast ? l10n.tourDone : l10n.tourNext,
              onNext: _advance,
              onSkip: isLast ? null : _finish,
              skipLabel: l10n.tourSkip,
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.title,
    required this.body,
    required this.step,
    required this.total,
    required this.nextLabel,
    required this.onNext,
    required this.onSkip,
    required this.skipLabel,
  });

  final String title;
  final String body;
  final int step;
  final int total;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback? onSkip;
  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.xs),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                Text(
                  '$step / $total',
                  style: theme.textTheme.bodySmall,
                  // Digits, and they read the same way in both languages —
                  // pinned so a Persian interface does not mirror "1 / 4".
                  textDirection: TextDirection.ltr,
                ),
                const Spacer(),
                if (onSkip != null)
                  TextButton(onPressed: onSkip, child: Text(skipLabel)),
                const SizedBox(width: NexSpacing.sm),
                FilledButton(onPressed: onNext, child: Text(nextLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrim with one rounded rectangle taken out of it.
///
/// `Path.combine(difference)` rather than a `BlendMode.clear` layer: clearing
/// into the overlay punches through everything under it, including the app
/// itself, and shows the black behind the window.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.color,
  });

  final Rect hole;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, cut),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.radius != radius || old.color != color;
}
