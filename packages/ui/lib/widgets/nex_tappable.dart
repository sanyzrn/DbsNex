import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// A control that is at least [nexMinTapTarget] across and says where the
/// keyboard is.
///
/// Two problems it exists to solve, both of which every custom control in the
/// app had:
///
/// * **Tap targets.** The filter pills were 34px tall and the type button 32,
///   against a token in this very package asking for 44 and platform guidance
///   asking for 48. They are horizontally scrolling targets, which is the
///   hardest case for accurate acquisition there is. The visual size is
///   unchanged here — the target grows around it.
/// * **Focus.** The only focus affordance in the app was a 16% fill tint: a
///   grey wash on a grey control. Windows is a shipped platform with its own CI
///   build and an installer, so "the keyboard is somewhere and you cannot see
///   where" is a state a real user reaches.
class NexTappable extends StatefulWidget {
  const NexTappable({
    super.key,
    required this.child,
    required this.onTap,
    required this.shape,
    this.semanticLabel,
    this.selected = false,
    this.minSize = nexMinTapTarget,
  });

  final Widget child;
  final VoidCallback onTap;

  /// The control's silhouette, **without a side** — the control draws its own
  /// border. This is only the outline the focus ring is shaped to.
  final ShapeBorder shape;

  final String? semanticLabel;
  final bool selected;
  final double minSize;

  @override
  State<NexTappable> createState() => _NexTappableState();
}

class _NexTappableState extends State<NexTappable> {
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : NexMotion.fast,
            curve: NexMotion.curve,
            child: ConstrainedBox(
              // Transparent padding out to the minimum, so the target is large
              // without the control looking it.
              constraints: BoxConstraints(
                minWidth: widget.minSize,
                minHeight: widget.minSize,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: widget.shape,
                    shadows: _focused
                        ? [
                            // A ring standing off the control, not a thicker
                            // border: a border change is indistinguishable from a
                            // selection change, and focus and selection are
                            // different things that can both be true at once.
                            BoxShadow(
                              color: scheme.primary,
                              spreadRadius:
                                  nexFocusRingOffset + nexFocusRingWidth,
                            ),
                            BoxShadow(
                              color: scheme.surface,
                              spreadRadius: nexFocusRingOffset,
                            ),
                          ]
                        : null,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
