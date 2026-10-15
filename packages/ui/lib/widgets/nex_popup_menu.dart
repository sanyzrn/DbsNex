import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_tokens.dart';

/// One bounded glass surface around a menu, rather than one blur per entry.
class NexPopupMenuButton<T> extends StatelessWidget {
  const NexPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.icon,
    this.child,
    this.enabled = true,
    this.padding = const EdgeInsets.all(NexSpacing.sm),
    this.offset = Offset.zero,
    this.position,
    this.shape,
    this.color,
    this.elevation,
    this.popUpAnimationStyle,
    this.borderRadius,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final VoidCallback? onOpened, onCanceled;
  final PopupMenuItemSelected<T>? onSelected;
  final String? tooltip;
  final Widget? icon, child;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final Offset offset;
  final PopupMenuPosition? position;
  final ShapeBorder? shape;
  final Color? color;
  final double? elevation;
  final AnimationStyle? popUpAnimationStyle;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final glass = context.nexVisualStyle.liquidGlass;
    return PopupMenuButton<T>(
      initialValue: glass ? null : initialValue,
      onOpened: onOpened,
      onSelected: onSelected,
      onCanceled: onCanceled,
      tooltip: tooltip,
      icon: icon,
      enabled: enabled,
      padding: padding,
      offset: offset,
      position: position,
      color: glass ? Colors.transparent : color,
      surfaceTintColor: glass ? Colors.transparent : null,
      elevation: glass ? 0 : elevation,
      shape: shape,
      popUpAnimationStyle: popUpAnimationStyle,
      borderRadius: borderRadius,
      menuPadding: glass ? EdgeInsets.zero : null,
      itemBuilder: (context) {
        final entries = itemBuilder(context);
        if (!glass || entries.isEmpty) return entries;
        return [_GlassMenuGroup<T>(entries: entries, selected: initialValue)];
      },
      child: child,
    );
  }
}

class _GlassMenuGroup<T> extends PopupMenuEntry<T> {
  const _GlassMenuGroup({required this.entries, this.selected});
  final List<PopupMenuEntry<T>> entries;
  final T? selected;

  @override
  double get height =>
      entries.fold(0, (height, entry) => height + entry.height);

  @override
  bool represents(T? value) => false;

  @override
  State<_GlassMenuGroup<T>> createState() => _GlassMenuGroupState<T>();
}

class _GlassMenuGroupState<T> extends State<_GlassMenuGroup<T>> {
  @override
  Widget build(BuildContext context) => NexGlassSurface(
    showShadow: false,
    fallbackColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(NexRadius.lg),
    padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in widget.entries)
            if (widget.selected != null && entry.represents(widget.selected))
              Semantics(
                selected: true,
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  child: entry,
                ),
              )
            else
              entry,
        ],
      ),
    ),
  );
}
