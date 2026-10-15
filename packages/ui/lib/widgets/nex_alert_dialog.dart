import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_tokens.dart';

/// Material's dialog layout, focus and actions with Nex's optional glass shell.
class NexAlertDialog extends AlertDialog {
  const NexAlertDialog({
    super.key,
    super.title,
    super.titlePadding,
    super.content,
    super.contentPadding,
    super.actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.scrollable,
    super.insetPadding,
    super.semanticLabel,
    super.backgroundColor,
    super.shape,
    super.icon,
  });

  @override
  Widget build(BuildContext context) {
    final dialog = super.build(context);
    if (!context.nexVisualStyle.liquidGlass || dialog is! Dialog) return dialog;
    final border = shape ?? Theme.of(context).dialogTheme.shape;
    final radius = border is RoundedRectangleBorder
        ? border.borderRadius.resolve(Directionality.of(context))
        : BorderRadius.circular(NexRadius.xl);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: dialog.insetPadding,
      insetAnimationDuration: dialog.insetAnimationDuration,
      insetAnimationCurve: dialog.insetAnimationCurve,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      shape: dialog.shape,
      semanticsRole: dialog.semanticsRole,
      child: NexGlassSurface(
        borderRadius: radius,
        fallbackColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Material(type: MaterialType.transparency, child: dialog.child),
      ),
    );
  }
}
