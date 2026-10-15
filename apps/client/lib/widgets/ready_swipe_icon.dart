import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:nex_ui/nex_ui.dart';

/// Ready-made, bundled vector motion; see third_party/swipe-icons-LICENSE.txt.
/// Scrubbing the composition follows the finger and reverses on retreat.
class NexReadySwipeIcon extends StatelessWidget {
  const NexReadySwipeIcon({
    super.key,
    required this.action,
    required this.progress,
    required this.color,
  });

  final NexSwipeAction action;
  final double progress;
  final Color color;

  static String asset(NexSwipeAction action) =>
      'assets/swipe/${switch (action) {
        NexSwipeAction.delete => 'delete',
        NexSwipeAction.addTag => 'tag',
        NexSwipeAction.pin => 'pin',
        NexSwipeAction.remind => 'remind',
        NexSwipeAction.share => 'share',
        NexSwipeAction.ask => 'ask',
      }}.json';

  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    child: Lottie.asset(
      asset(action),
      controller: AlwaysStoppedAnimation(
        MediaQuery.disableAnimationsOf(context) ? 0 : progress.clamp(0, 1),
      ),
      animate: false,
      repeat: false,
      frameRate: FrameRate.max,
      fit: BoxFit.contain,
    ),
  );
}
