import 'package:flutter/material.dart';
import '../tokens/nex_tokens.dart';

/// Size and fade transition without rebuilding a stable child on each tick.
class NexReveal extends StatefulWidget {
  const NexReveal({
    super.key,
    required this.visible,
    required this.child,
    this.maintainState = false,
  });
  final bool visible, maintainState;
  final Widget child;
  @override
  State<NexReveal> createState() => _NexRevealState();
}

class _NexRevealState extends State<NexReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: NexMotion.morph,
    reverseDuration: NexMotion.slow,
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_settled);
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: NexMotion.curve,
    reverseCurve: NexMotion.exitCurve,
  );
  bool _reduced = false;
  void _settled(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) _controller.value = widget.visible ? 1 : 0;
  }

  @override
  void didUpdateWidget(NexReveal old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    if (_reduced) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.visible,
    child: ExcludeSemantics(
      excluding: !widget.visible,
      child: SizeTransition(
        sizeFactor: _curve,
        axisAlignment: -1,
        child: FadeTransition(
          opacity: _curve,
          child: TickerMode(
            enabled: widget.visible,
            child: Offstage(
              offstage: !widget.visible && _controller.isDismissed,
              child:
                  widget.visible ||
                      widget.maintainState ||
                      !_controller.isDismissed
                  ? widget.child
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
}
