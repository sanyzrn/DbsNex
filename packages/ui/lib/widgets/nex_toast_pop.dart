import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// Runs a toast content's own exit — see [NexToastPop].
///
/// The host creates one, hands it to the [NexToastPop] it wraps, and calls
/// [dismiss] instead of removing the widget outright.
class NexToastPopController {
  _NexToastPopState? _state;

  bool get isAttached => _state != null;

  void dismiss() => unawaited(_state?._leave());
}

/// Gives a toast's content a small entrance "pop" — scaling up past 1.0 and
/// settling back, rather than only fading in at a flat, linear rate — and a
/// matching exit of its own: a settle toward 0.92 and away on the exit token.
///
/// This wraps the content passed to the capsule presenter; the capsule
/// itself still slides and fades via whatever presents it, which is not
/// something a descendant widget can reach or override. Giving the whole
/// capsule a from-scratch entrance *and* exit — closer to how a Dynamic
/// Island notification expands and collapses — would mean replacing the
/// presenter everywhere a toast is shown in the app, which is out of
/// proportion to a cosmetic flourish. So both motions stay scoped to the
/// one thing every toast funnels through: its content widget — the entrance
/// on creation, the exit when the host says [NexToastPopController.dismiss]
/// and takes the content down from [NexToastPop.onGone].
class NexToastPop extends StatefulWidget {
  const NexToastPop({
    super.key,
    required this.child,
    this.controller,
    this.onGone,
  });

  final Widget child;

  /// The host's handle on this toast's exit.
  final NexToastPopController? controller;

  /// Called once the exit has finished — the moment to take the content
  /// down. Omit it and the content simply rests invisible, still mounted.
  final VoidCallback? onGone;

  @override
  State<NexToastPop> createState() => _NexToastPopState();
}

class _NexToastPopState extends State<NexToastPop>
    with TickerProviderStateMixin {
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

  // The exit: the entrance run small — a settle toward 0.92 with a fade, on
  // the exit token. Local to the content, because the capsule's own
  // transition belongs to whoever is presenting it; a toast that landed
  // with a pop and left with nothing read as half-built, which it was.
  late final _exitController = AnimationController(
    vsync: this,
    duration: NexMotion.exit,
  );
  late final _exitScale = Tween<double>(
    begin: 1.0,
    end: 0.92,
  ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));
  late final _exitFade = CurvedAnimation(
    parent: _exitController,
    curve: Curves.easeIn,
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    // Posted rather than run inline: `MediaQuery` is not reliably reachable
    // from `initState` itself, only once the first frame's dependencies are
    // wired up — the same reason `CommitReceipt` defers its own start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        _exitController.duration = Duration.zero;
        return;
      }
      _controller.forward();
    });
  }

  @override
  void didUpdateWidget(NexToastPop old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    final controller = widget.controller;
    if (controller?._state == this) controller?._state = null;
    _controller.dispose();
    _exitController.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await _exitController.forward();
    if (!mounted) return;
    widget.onGone?.call();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _exitFade,
    child: ScaleTransition(
      scale: _exitScale,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    ),
  );
}
