import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_tokens.dart';

/// One floating home dock. The capture button rises out of the same surface
/// as the four quieter destinations instead of separating them into islands.
///
/// The empty centre is a real gap in the hit targets: a tap beside capture
/// cannot accidentally open a different destination underneath it.
class NexNavigationDock extends StatelessWidget {
  const NexNavigationDock({
    super.key,
    required this.leading,
    required this.capture,
    required this.trailing,
    this.recede,
    this.away = false,
  });

  final List<Widget> leading;
  final Widget capture;
  final List<Widget> trailing;

  /// How far the four destinations have stepped back: 0 with the whole dock
  /// there, 1 with only capture left. The home screen runs it while someone
  /// reads down the list, so the notes have the bottom of the screen and the
  /// one primary action never moves from under the thumb.
  ///
  /// A fade and nothing else, on purpose: it is drawn by the render object,
  /// so a scroll that sets it going rebuilds no widget while it runs.
  final Animation<double>? recede;

  /// Whether the destinations are stepped back. Faded out they must not be
  /// tappable or read out either: a control nobody can see is a trap.
  final bool away;

  static const height = 64.0;
  static const lift = 24.0;
  static const maxWidth = 352.0;
  static const _centreGap = 72.0;

  @override
  Widget build(BuildContext context) {
    assert(leading.length == 2 && trailing.length == 2);
    final visual = context.nexVisualStyle;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final viewport = MediaQuery.sizeOf(context).width;
    // On a narrow window the outer margin gives way before any 48dp target
    // does. The five controls need 256dp even at their tightest spacing.
    final width = (viewport < 304 ? viewport : viewport - NexSpacing.md * 2)
        .clamp(0.0, maxWidth);
    final narrow = width < 288;
    final edge = narrow ? NexSpacing.xs : NexSpacing.sm;
    final gap = narrow ? 56.0 : _centreGap;
    final radius = BorderRadius.circular(height / 2);
    final actions = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: edge),
        child: Row(
          // Places stay put when the interface language changes. The text in
          // tooltips still inherits the ambient direction.
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final action in leading)
              SizedBox.square(dimension: nexMinTapTarget, child: action),
            SizedBox(width: gap),
            for (final action in trailing)
              SizedBox.square(dimension: nexMinTapTarget, child: action),
          ],
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: height + lift,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: _stepBack(
              Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // Dark and Night separate by tone; Light gets a quiet lift.
                  // Glass already paints its own optical edge and shadow.
                  boxShadow: visual.liquidGlass || dark
                      ? null
                      : [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                // Paint after the opaque surface so it cannot cover the edge.
                foregroundDecoration: visual.liquidGlass
                    ? null
                    : BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: highContrast
                              ? scheme.outline
                              : scheme.outlineVariant,
                          width: highContrast ? 1 : 0.75,
                        ),
                      ),
                child: NexGlassSurface(
                  material: NexGlassMaterial.floating,
                  borderRadius: radius,
                  // White in Light; the elevated neutral tone in Dark/Night.
                  fallbackColor: dark
                      ? scheme.surfaceContainerHigh
                      : scheme.surface,
                  child: actions,
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: Center(child: capture)),
        ],
      ),
    );
  }
}

extension on NexNavigationDock {
  /// The capsule and its four destinations, fading with [recede] and out of
  /// reach of a finger or a screen reader while [away].
  Widget _stepBack(Widget capsule) {
    final recede = this.recede;
    return IgnorePointer(
      ignoring: away,
      child: ExcludeSemantics(
        excluding: away,
        child: recede == null
            ? capsule
            : FadeTransition(
                key: const ValueKey('dock-destinations'),
                opacity: recede.drive(Tween(begin: 1.0, end: 0.0)),
                child: capsule,
              ),
      ),
    );
  }
}

/// A full-sized destination in the home dock, with a fixed place for a badge.
///
/// Under a finger its glyph gives a little and springs back on the way up:
/// the dock's four places have no labels, so the press itself is what says
/// "this one" before the page it leads to arrives.
class NexDockAction extends StatefulWidget {
  const NexDockAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget? badge;

  @override
  State<NexDockAction> createState() => _NexDockActionState();
}

class _NexDockActionState extends State<NexDockAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: InkResponse(
      onTap: widget.onPressed,
      onHighlightChanged: (down) {
        if (down != _pressed) setState(() => _pressed = down);
      },
      radius: nexMinTapTarget / 2,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AnimatedScale(
                scale: _pressed ? 0.86 : 1,
                duration: NexMotion.of(
                  context,
                  _pressed ? NexMotion.fast : NexMotion.pop,
                ),
                curve: _pressed ? NexMotion.curve : NexMotion.popCurve,
                child: Icon(widget.icon, size: 22),
              ),
            ),
            if (widget.badge case final mark?)
              Positioned(top: 9, right: 9, child: mark),
          ],
        ),
      ),
    ),
  );
}
