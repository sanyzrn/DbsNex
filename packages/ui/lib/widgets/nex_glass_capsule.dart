import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';

/// A row of actions sharing one pill of glass.
///
/// The geometry is Apple's, read out of the iOS 27 kit's
/// `Toolbar - Bottom - iPhone`: a 48pt pill, and symbols whose centres sit 54
/// apart with the first one 24 in from the end. The kit spends that on a 36pt
/// symbol with 18 between and 6 at each end; this spends it on a 48pt tap
/// target with 6 between and none at the ends, which comes out at the same
/// width with the same centres and does not ask anybody to hit a 36pt button.
///
/// The part actually worth copying is the sharing. Four separate bubbles
/// along the bottom of a screen read as four unrelated things; two pills of
/// two read as two pairs, which is what they are — the things that change
/// what you are looking at, and the things that change the app.
class NexGlassCapsule extends StatelessWidget {
  const NexGlassCapsule({super.key, required this.children});

  /// One per action. Each gets a square [height]-by-[height] slot.
  final List<Widget> children;

  static const height = 48.0;

  /// What the kit leaves between two symbols, less the space the wider tap
  /// target already took — see the class comment.
  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    final radius = BorderRadius.circular(height / 2);
    // Transparent, but a `Material` all the same: without one here the ink
    // from a tap lands on the Scaffold's own material, which is *behind* the
    // glass, so the splash happens and nobody sees it.
    final row = Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox.square(dimension: height, child: children[i]),
          ],
        ],
      ),
    );
    if (visual.liquidGlass) {
      return SizedBox(
        height: height,
        child: NexGlassSurface(borderRadius: radius, child: row),
      );
    }
    // Outside the glass appearance this still cannot be nothing: it floats
    // over a scrolling list, and icons with no surface under them sit on
    // whatever line of somebody's note happens to be passing.
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: row,
      ),
    );
  }
}

/// One action in a [NexGlassCapsule].
///
/// An [IconButton] of its own would bring its own 40pt constraints and its
/// own splash bounds, neither of which match the slot the capsule hands it;
/// this fills the slot exactly, so the ripple is the tap target.
class NexCapsuleAction extends StatelessWidget {
  const NexCapsuleAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Drawn over the icon's top-right corner — the update dot, and nothing
  /// else so far.
  ///
  /// Right, not trailing: the bar this sits in does not mirror, so neither
  /// does anything pinned to a corner of it.
  final Widget? badge;

  /// What the kit draws inside the 36pt symbol box.
  static const iconSize = 22.0;

  @override
  Widget build(BuildContext context) {
    final mark = badge;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: NexGlassCapsule.height / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: Semantics(
          button: true,
          label: tooltip,
          // Expanded, so the badge is placed against the slot rather than
          // against the glyph: a Stack sized to its Icon is 22 across, and
          // ten in from the corner of *that* lands the dot in the middle of
          // the gear.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: Icon(icon, size: iconSize)),
              if (mark != null) Positioned(top: 10, right: 10, child: mark),
            ],
          ),
        ),
      ),
    );
  }
}
