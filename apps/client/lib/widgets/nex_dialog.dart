import 'package:flutter/material.dart';

import 'package:nex_ui/nex_ui.dart';

/// Wraps dialog content at a stable width.
///
/// `AlertDialog` sizes itself to its content's intrinsic width, so a dialog
/// holding a text field started as a narrow box and widened with every word
/// typed into it. Every dialog in the app is the same width now, capped so it
/// does not stretch across a desktop window.
class NexDialogBody extends StatelessWidget {
  const NexDialogBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      // maxFinite lets the dialog take the width its own constraints allow,
      // which is the platform's dialog width rather than the content's.
      width: width < 420 ? double.maxFinite : 380,
      child: child,
    );
  }
}

/// A bottom sheet body that always fills the sheet's width.
class NexSheetBody extends StatelessWidget {
  const NexSheetBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(NexSpacing.lg),
          child: child,
        ),
      );
}
