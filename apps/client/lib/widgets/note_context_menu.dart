import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        if (widget.onPin != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.push_pin_outlined),
            onPressed: widget.onPin,
            child: Text(widget.pinned ? l10n.unpin : l10n.pin),
          ),
        if (widget.onCopy != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.copy_outlined),
            onPressed: widget.onCopy,
            child: Text(l10n.copy),
          ),
        if (widget.onEdit != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.edit_outlined),
            onPressed: widget.onEdit,
            child: Text(l10n.edit),
          ),
        if (widget.onRemind != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.notifications_outlined),
            onPressed: widget.onRemind,
            child: Text(l10n.remind),
          ),
        MenuItemButton(onPressed: widget.onOpen, child: Text(l10n.open)),
        MenuItemButton(onPressed: widget.onAddTag, child: Text(l10n.addTag)),
        MenuItemButton(onPressed: widget.onDelete, child: Text(l10n.delete)),
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
