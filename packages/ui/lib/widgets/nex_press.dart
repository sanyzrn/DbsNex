import 'package:flutter/material.dart';
import '../tokens/nex_tokens.dart';

/// Adds a gentle press response without taking over a control's gestures.
class NexPress extends StatefulWidget {
  const NexPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<NexPress> createState() => _NexPressState();
}

class _NexPressState extends State<NexPress> {
  int? _pointer;
  @override
  void didUpdateWidget(NexPress old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _pointer = null;
  }

  void _release(PointerEvent event) {
    if (mounted && _pointer == event.pointer) setState(() => _pointer = null);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (widget.enabled && _pointer == null) {
        setState(() => _pointer = event.pointer);
      }
    },
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedScale(
      scale: _pointer != null && !MediaQuery.disableAnimationsOf(context)
          ? 0.97
          : 1,
      duration: NexMotion.of(context, NexMotion.fast),
      curve: NexMotion.curve,
      child: widget.child,
    ),
  );
}
