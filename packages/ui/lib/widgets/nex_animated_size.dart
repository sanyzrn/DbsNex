import 'package:flutter/material.dart';
import '../tokens/nex_tokens.dart';

/// Implicit sizing for content that has no explicit height. Reduced motion
/// bypasses the animation, including Flutter's zero-duration layout ticker.
class NexAnimatedSize extends StatefulWidget {
  const NexAnimatedSize({super.key, required this.child});
  final Widget child;
  @override
  State<NexAnimatedSize> createState() => _NexAnimatedSizeState();
}

class _NexAnimatedSizeState extends State<NexAnimatedSize> {
  // Switching the system's motion preference must keep async reading content
  // (for example an already requested translation) rather than recreating it.
  // Native editors use a fixed hierarchy and an explicit AnimatedContainer.
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return MediaQuery.disableAnimationsOf(context)
        ? content
        : AnimatedSize(
            duration: NexMotion.morph,
            reverseDuration: NexMotion.slow,
            curve: NexMotion.curve,
            alignment: Alignment.topCenter,
            child: content,
          );
  }
}
