import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The visible answer to "there is no Save button".
///
/// A bar in the accent along the card's leading edge, fading out over
/// [NexMotion.receipt] — the equivalent of ink drying. It appears exactly once
/// per capture and interrupts nothing.
///
/// What it replaces was an `AnimatedSlide` of `Offset(0, -0.02)`: under two
/// logical pixels on a 120px card, which is below the threshold most people can
/// perceive. And the id driving it was never cleared, so rather than an
/// animation it was a permanent two-pixel misalignment on whichever note was
/// captured last.
class CommitReceipt extends StatefulWidget {
  const CommitReceipt({
    super.key,
    required this.active,
    required this.onDone,
    required this.child,
  });

  final bool active;

  /// Called when the receipt has faded, so the caller can forget which note it
  /// was for. Without this the state is permanent rather than momentary.
  final VoidCallback onDone;

  final Widget child;

  @override
  State<CommitReceipt> createState() => _CommitReceiptState();
}

class _CommitReceiptState extends State<CommitReceipt>
    with SingleTickerProviderStateMixin {
  // Created here rather than lazily. Every card except the one just captured
  // is inactive, so `build` returns the child without ever touching the
  // controller — which made `dispose` the first access, creating a ticker
  // against an element that had already been deactivated.
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: NexMotion.receipt,
      value: widget.active ? 1 : 0,
    );
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(CommitReceipt old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        // Still a receipt, just an instantaneous one: the caller must be told
        // either way, or the id it holds is never released.
        widget.onDone();
        return;
      }
      _fade.reverse(from: 1).whenComplete(() {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        // Inside the card's own gutter and clipped to its radius, so the bar
        // sits on the card rather than floating beside it.
        PositionedDirectional(
          top: nexCardInsets.top,
          bottom: nexCardInsets.bottom,
          start: nexCardInsets.left,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(NexRadius.xs),
                    right: Radius.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
