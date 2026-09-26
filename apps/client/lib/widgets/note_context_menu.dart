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
  });
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onAddTag;
  final VoidCallback onDelete;
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
