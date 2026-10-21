import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_contrast.dart';
import '../tokens/nex_tokens.dart';

/// Shared content for a card menu and a link's context menu.
class NexMenuEntryContent extends StatelessWidget {
  const NexMenuEntryContent({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: NexSpacing.md),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// The width every menu in the app is at least, and at most. The card's hold
/// menu, a date heading's menu, a page's ⋮ menu and a picker all share it, so
/// no two menus are two widths.
const nexMenuConstraints = BoxConstraints(minWidth: 180, maxWidth: 320);

/// A dropdown field's list is a menu too: the same corners and surface as
/// every other, set with these two on `DropdownButton` and
/// `DropdownButtonFormField` (their own defaults are a square canvas).
BorderRadius get nexDropdownRadius => BorderRadius.circular(NexRadius.lg);
Color nexDropdownColor(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHigh;

/// The ink of a menu line that destroys something. Under the glass material
/// the plain error colour can fall below readable contrast, so it is nudged
/// until it reads on the floating surface.
Color nexMenuErrorColor(BuildContext context) {
  final theme = Theme.of(context);
  return context.nexVisualStyle.liquidGlass &&
          !MediaQuery.highContrastOf(context)
      ? nexReadableOn(
          theme.colorScheme.error,
          context.nexVisualStyle.floatingContrastGround(theme.brightness),
        )
      : theme.colorScheme.error;
}

/// One line of any menu in the app: an icon, the words, and red for what
/// destroys. This is the card's hold menu, the reference every other menu is
/// held to (`docs/16-design-language.md` §10) — never a bare [PopupMenuItem]
/// with a [Text], which is how the page menus ended up smaller, plainer and
/// without icons.
///
/// [icon] may be left out for a menu that chooses one of several values (a
/// currency, a repeat): the selected line is then marked by the menu itself.
PopupMenuItem<T> nexMenuItem<T>({
  Key? key,
  required T value,
  IconData? icon,
  required String label,
  bool destructive = false,
  bool enabled = true,
}) => PopupMenuItem<T>(
  key: key,
  value: value,
  enabled: enabled,
  height: 48,
  padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
  child: Builder(
    builder: (context) {
      final tint = destructive ? nexMenuErrorColor(context) : null;
      return icon == null
          ? Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tint),
            )
          : NexMenuEntryContent(icon: icon, label: label, color: tint);
    },
  ),
);

/// The same floating material and corners as the card's hold menu, at a
/// pointer position rather than a button. A single blur surrounds all rows.
Future<T?> nexShowContextMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  final glass = context.nexVisualStyle.liquidGlass;
  return showMenu<T>(
    context: context,
    position: position,
    constraints: nexMenuConstraints,
    color: glass
        ? Colors.transparent
        : Theme.of(context).colorScheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
    elevation: glass ? 0 : 3,
    menuPadding: glass
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(vertical: NexSpacing.sm),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NexRadius.lg),
    ),
    items: glass ? [_GlassMenuGroup<T>(entries: items)] : items,
  );
}

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
    final scheme = Theme.of(context).colorScheme;
    // The card's hold menu is the reference: the same width, corners, surface,
    // shadow and padding unless a caller has a reason to differ.
    return PopupMenuButton<T>(
      constraints: nexMenuConstraints,
      popUpAnimationStyle:
          popUpAnimationStyle ??
          AnimationStyle(duration: NexMotion.standard, curve: NexMotion.curve),
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
      color: glass
          ? Colors.transparent
          : (color ?? scheme.surfaceContainerHigh),
      surfaceTintColor: Colors.transparent,
      elevation: glass ? 0 : (elevation ?? 3),
      shape:
          shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NexRadius.lg),
          ),
      borderRadius: borderRadius,
      menuPadding: glass
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: NexSpacing.sm),
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
    material: NexGlassMaterial.floating,
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
