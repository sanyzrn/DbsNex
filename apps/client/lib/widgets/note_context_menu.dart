import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/hold_menu.dart';

/// One line of a note's hold menu: what it is, and what pressing it does.
class NoteMenuEntry {
  const NoteMenuEntry(this.action, this.onPressed, {this.label, this.icon});

  final NexHoldAction action;
  final VoidCallback onPressed;

  /// Overrides for a line whose words depend on the note — Unpin for a
  /// pinned note, Collapse for an expanded card.
  final String? label;
  final IconData? icon;
}

/// The note's hold menu, also reached with a secondary click or the
/// keyboard's menu key.
///
/// What it lists is decided by the caller from [NexHoldAction] and the
/// user's choice in Settings; this widget only draws it.
class NoteContextMenu extends StatefulWidget {
  const NoteContextMenu({
    super.key,
    required this.child,
    required this.entries,
  });
  final Widget child;
  final List<NoteMenuEntry> entries;
  @override
  State<NoteContextMenu> createState() => _NoteContextMenuState();
}

class _NoteMenuIntent extends Intent {
  const _NoteMenuIntent();
}

class _NoteContextMenuState extends State<NoteContextMenu> {
  final _controller = MenuController();

  /// The screen's tap rule (W4.5), or one of this menu's own where the screen
  /// has none. The card the menu was opened from sits inside the menu's own
  /// tap region, so `consumeOutsideTap` never sees a tap on it; the guard is
  /// what makes that tap close the menu and do nothing else.
  final _ownGuard = NexTapGuardController();
  NexTapGuardController? _screenGuard;
  NexTapGuardController get _guard => _screenGuard ?? _ownGuard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Looked up here, not when the menu closes: it can close while this
    // element is being taken down, when looking up an ancestor is an error.
    _screenGuard = NexTapGuard.maybeOf(context);
  }

  void _opened() => _guard.open(this, close: _controller.close);
  void _closed() => _guard.closed(this);

  @override
  void dispose() {
    _ownGuard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      // A tap outside closes the menu and does nothing else, like the date
      // heading's menu (a modal popup). Without this the same tap went on to
      // whatever was under it — opening another note, or pressing a button.
      consumeOutsideTap: true,
      onOpen: _opened,
      onClose: _closed,
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
        for (final entry in widget.entries)
          item(
            entry.icon ?? entry.action.icon,
            entry.label ?? entry.action.label(context),
            entry.onPressed,
            // In the error colour, like every other delete in Nex.
            destructive: entry.action == NexHoldAction.delete,
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
                if (widget.entries.isNotEmpty) controller.open();
                return null;
              },
            ),
          },
          // With every action turned off in Settings there is no menu, and
          // a hold does nothing rather than opening an empty box.
          child: GestureDetector(
            onLongPressStart: widget.entries.isEmpty
                ? null
                : (details) => controller.open(position: details.localPosition),
            onSecondaryTapDown: widget.entries.isEmpty
                ? null
                : (details) => controller.open(position: details.localPosition),
            // A tap on the card that owns the open menu closes the menu and
            // nothing else, the same as a tap anywhere outside it. The card
            // stays in the tree either way, so an expanded card does not fold
            // when its menu opens.
            child: NexTapGuarded(controller: _guard, child: child!),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
