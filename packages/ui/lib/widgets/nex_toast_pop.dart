import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// Gives a toast's content a small entrance "pop" — scaling up past 1.0 and
/// settling back, rather than only fading in at a flat, linear rate.
///
/// This wraps the content passed to [SnackBar]; the capsule itself still
/// slides and fades in via Flutter's own [SnackBar] transition, which is not
/// something a descendant widget can reach or override. Giving the whole
/// capsule a from-scratch entrance *and* exit — closer to how a Dynamic
/// Island notification expands and collapses — would mean replacing
/// `ScaffoldMessenger` with a custom overlay-based presenter everywhere a
/// toast is shown in the app. That is out of proportion to a cosmetic
/// flourish, so this stays scoped to the one thing every toast already
/// funnels through: its content widget.
class NexToastPop extends StatefulWidget {
  const NexToastPop({super.key, required this.child});

  final Widget child;

  @override
  State<NexToastPop> createState() => _NexToastPopState();
}

class _NexToastPopState extends State<NexToastPop>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: NexMotion.toastPop,
  );
  // Not 0→1: a toast is wide and short, so scaling it up from nothing reads
  // as a dot expanding sideways into a capsule — exactly the "circle opening
  // in the middle" look this was meant to avoid — rather than as a pop.
  // Starting close to full size keeps the overshoot-and-settle character
  // from easeOutBack while making the motion a subtle settle, not a growth.
  late final _scale = Tween<double>(
    begin: 0.86,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  late final _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    // Posted rather than run inline: `MediaQuery` is not reliably reachable
    // from `initState` itself, only once the first frame's dependencies are
    // wired up — the same reason `CommitReceipt` defers its own start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}
