import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// Secondary pointer and keyboard access to the same timeline actions.
class NoteContextMenu extends StatefulWidget {
  const NoteContextMenu({
    super.key,
    required this.child,
    required this.onOpen,
    required this.onAddTag,
    required this.onDelete,
    this.onPin,
    this.onCopy,
    this.onEdit,
    this.onRemind,
    this.pinned = false,
  });
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onAddTag;
  final VoidCallback onDelete;
  final VoidCallback? onPin, onCopy, onEdit, onRemind;
  final bool pinned;
  @override
  State<NoteContextMenu> createState() => _NoteContextMenuState();
}

class _NoteMenuIntent extends Intent {
  const _NoteMenuIntent();
}

class _NoteContextMenuState extends State<NoteContextMenu> {
  final _controller = MenuController();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The same menu as a date heading's: rounded, on a raised surface, and
    // an icon on every line. It was the stock square menu, with icons on
    // four of its seven items and Delete in the same ink as Copy.
    Widget item(
      IconData icon,
      String label,
      VoidCallback? onPressed, {
      bool destructive = false,
    }) {
      final tint = destructive ? scheme.error : scheme.onSurface;
      return MenuItemButton(
        onPressed: onPressed,
        leadingIcon: Icon(icon, size: 20, color: tint),
        style: MenuItemButton.styleFrom(
          foregroundColor: tint,
          iconColor: tint,
          minimumSize: const Size(180, 48),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
          ),
          textStyle: theme.textTheme.bodyMedium,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
          child: Text(label),
        ),
      );
    }

    return MenuAnchor(
      controller: _controller,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: NexSpacing.sm),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NexRadius.lg),
          ),
        ),
      ),
      menuChildren: [
        if (widget.onPin != null)
          item(
            widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            widget.pinned ? l10n.unpin : l10n.pin,
            widget.onPin,
          ),
        if (widget.onCopy != null)
          item(Icons.copy_outlined, l10n.copy, widget.onCopy),
        if (widget.onEdit != null)
          item(Icons.edit_outlined, l10n.edit, widget.onEdit),
        if (widget.onRemind != null)
          item(Icons.notifications_outlined, l10n.remind, widget.onRemind),
        item(Icons.label_outline, l10n.addTag, widget.onAddTag),
        item(Icons.open_in_new, l10n.open, widget.onOpen),
        // Last, and in the error colour, like every other delete in Nex.
        item(
          Icons.delete_outline,
          l10n.delete,
          widget.onDelete,
          destructive: true,
        ),
      ],
      builder: (context, controller, child) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.contextMenu): _NoteMenuIntent(),
          SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _NoteMenuIntent(),
        },
        child: Actions(
          actions: {
            _NoteMenuIntent: CallbackAction<_NoteMenuIntent>(
              onInvoke: (_) {
                controller.open();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onLongPressStart: (details) =>
                controller.open(position: details.localPosition),
            onSecondaryTapDown: (details) =>
                controller.open(position: details.localPosition),
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
