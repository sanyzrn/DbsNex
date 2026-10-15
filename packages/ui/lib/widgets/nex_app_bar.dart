import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/nex_appearance.dart';

/// A page header that follows the same material as the navigation dock.
/// Ordinary app bars keep their original theme when glass is switched off.
class NexAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NexAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.flexibleSpace,
    this.titleSpacing,
    this.bottom,
  });

  final Widget? title, leading, flexibleSpace;
  final List<Widget>? actions;
  final bool? centerTitle;
  final Color? backgroundColor, foregroundColor;
  final double? elevation;
  final double? titleSpacing;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final glass = context.nexVisualStyle.liquidGlass;
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      backgroundColor: glass ? Colors.transparent : backgroundColor,
      foregroundColor: foregroundColor,
      elevation: glass ? 0 : elevation,
      scrolledUnderElevation: glass ? 0 : null,
      surfaceTintColor: glass ? Colors.transparent : null,
      // Transparent has no meaningful brightness. Keep system icons tied to
      // the actual glass palette instead of treating its alpha as black.
      systemOverlayStyle: glass
          ? (Theme.of(context).appBarTheme.systemOverlayStyle ??
                    (Theme.of(context).brightness == Brightness.dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark))
                .copyWith(statusBarColor: Colors.transparent)
          : null,
      forceMaterialTransparency: glass,
      flexibleSpace: flexibleSpace ?? (glass ? const NexGlassBar() : null),
    );
  }
}
