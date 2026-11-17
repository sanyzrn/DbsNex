import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// The shared detail control, with a static open body for reduced motion.
/// Flutter's zero-duration AnimatedSize can invalidate itself during layout
/// when the open body changes height. A static body also honours that setting.
class GoldDetails extends StatelessWidget {
  const GoldDetails({
    super.key,
    required this.open,
    required this.onChanged,
    required this.title,
    required this.child,
    this.hint,
    this.toggleKey,
  });
  final bool open;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? hint;
  final Key? toggleKey;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (open && MediaQuery.disableAnimationsOf(context)) return child;
    return NexMoreDetails(
      open: open,
      onChanged: onChanged,
      title: title,
      hint: hint,
      toggleKey: toggleKey,
      child: child,
    );
  }
}
