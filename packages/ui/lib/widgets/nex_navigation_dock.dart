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
  });

  final List<Widget> leading;
  final Widget capture;
  final List<Widget> trailing;

  static const height = 64.0;
  static const lift = 24.0;
  static const maxWidth = 352.0;
  static const _centreGap = 72.0;

  @override
  Widget build(BuildContext context) {
    assert(leading.length == 2 && trailing.length == 2);
    final visual = context.nexVisualStyle;
    final scheme = Theme.of(context).colorScheme;
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: visual.liquidGlass
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: NexGlassSurface(
                borderRadius: radius,
                fallbackColor: scheme.surfaceContainerLowest,
                child: actions,
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: Center(child: capture)),
        ],
      ),
    );
  }
}

/// A full-sized destination in the home dock, with a fixed place for a badge.
class NexDockAction extends StatelessWidget {
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
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onPressed,
      radius: nexMinTapTarget / 2,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        label: tooltip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: Icon(icon, size: 22)),
            if (badge case final mark?)
              Positioned(top: 9, right: 9, child: mark),
          ],
        ),
      ),
    ),
  );
}
