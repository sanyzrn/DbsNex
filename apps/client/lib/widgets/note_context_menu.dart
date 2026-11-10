import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/hold_menu.dart';

/// One line of a note's hold menu: what it is, and what pressing it does.
class NoteMenuEntry {
  const NoteMenuEntry(
    this.action,
    this.onPressed, {
    this.label,
    this.icon,
    this.subtitle,
  });

  final NexHoldAction action;
  final VoidCallback onPressed;

  /// Overrides for a line whose words depend on the note — Unpin for a
  /// pinned note, Collapse for an expanded card.
  final String? label;
  final IconData? icon;

  /// Optional subdued second line, shown only when relevant.
  final String? subtitle;
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
    this.entries = const [],
    this.entriesBuilder,
  });
  final Widget child;
  final List<NoteMenuEntry> entries;
  final List<NoteMenuEntry> Function(BuildContext context, double width)?
  entriesBuilder;
  @override
  State<NoteContextMenu> createState() => _NoteContextMenuState();
}

class _NoteMenuIntent extends Intent {
  const _NoteMenuIntent();
}

class _NoteContextMenuState extends State<NoteContextMenu> {
  final _controller = MenuController();
  List<NoteMenuEntry>? _resolved;

  /// Whether the menu is up. All the card does with that is duck, briefly
  /// (see the `AnimatedScale` in [build]): the finger that held it sees the
  /// card itself answer, rather than nothing moving until words appear.
  bool _isOpen = false;
  bool _ducking = false;

  void _open([Offset? position]) {
    final builder = widget.entriesBuilder;
    if (builder == null) {
      if (widget.entries.isNotEmpty) _controller.open(position: position);
      return;
    }
    final entries = builder(context, context.size!.width);
    setState(() => _resolved = entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && entries.isNotEmpty) _controller.open(position: position);
    });
  }

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

  void _opened() {
    // The tick the hold itself never gave: this is the moment the press
    // became a menu, and the card agrees by ducking a hair for
    // [NexMotion.fast].
    nexTick();
    if (mounted && !_isOpen) {
      setState(() {
        _isOpen = true;
        _ducking = true;
      });
    }
    _guard.open(this, close: _controller.close);
  }

  void _closed() {
    // The menu can close while this element is already being taken down —
    // the same timing didChangeDependencies above guards against.
    if (mounted && _isOpen) {
      setState(() {
        _isOpen = false;
        _ducking = false;
      });
    }
    _guard.closed(this);
  }

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
      String? subtitle,
    }) {
      final error =
          context.nexVisualStyle.liquidGlass &&
              !MediaQuery.highContrastOf(context)
          ? nexReadableOn(
              scheme.error,
              context.nexVisualStyle.floatingContrastGround(theme.brightness),
            )
          : scheme.error;
      final tint = destructive ? error : scheme.onSurface;
      return MenuItemButton(
        onPressed: onPressed,
        style: MenuItemButton.styleFrom(
          foregroundColor: tint,
          iconColor: tint,
          minimumSize: const Size(180, 48),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
          ),
          textStyle: theme.textTheme.bodyMedium,
        ),
        child: NexMenuEntryContent(
          icon: icon,
          label: label,
          subtitle: subtitle,
          color: tint,
        ),
      );
    }

    final glass = context.nexVisualStyle.liquidGlass;
    final entries = [
      for (final entry in _resolved ?? widget.entries)
        item(
          entry.icon ?? entry.action.icon,
          entry.label ?? entry.action.label(context),
          entry.onPressed,
          destructive: entry.action == NexHoldAction.delete,
          subtitle: entry.subtitle,
        ),
    ];
    return MenuAnchor(
      controller: _controller,
      // A tap outside closes the menu and does nothing else, like the date
      // heading's menu (a modal popup). Without this the same tap went on to
      // whatever was under it — opening another note, or pressing a button.
      consumeOutsideTap: true,
      onOpen: _opened,
      onClose: _closed,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          glass ? Colors.transparent : scheme.surfaceContainerHigh,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(
          glass || context.nexVisualStyle.minimal ? 0 : 3,
        ),
        padding: WidgetStatePropertyAll(
          glass
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(vertical: NexSpacing.sm),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NexRadius.lg),
          ),
        ),
      ),
      menuChildren: glass
          ? [
              NexGlassSurface(
                material: NexGlassMaterial.floating,
                showShadow: false,
                fallbackColor: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(NexRadius.lg),
                padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: entries,
                ),
              ),
            ]
          : entries,
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
                _open();
                return null;
              },
            ),
          },
          // With every action turned off in Settings there is no menu, and
          // a hold does nothing rather than opening an empty box.
          child: GestureDetector(
            onLongPressStart:
                widget.entries.isEmpty && widget.entriesBuilder == null
                ? null
                // The touch location is the platform's established,
                // screen-aware anchor. Forcing y=0 or the full card height
                // moves the menu off screen for cards near either edge.
                : (details) => _open(details.localPosition),
            onSecondaryTapDown:
                widget.entries.isEmpty && widget.entriesBuilder == null
                ? null
                // A mouse expects the menu at its cursor, wherever on the
                // card that lands — the touch rules are not its rules.
                : (details) => _open(details.localPosition),
            // A tap on the card that owns the open menu closes the menu and
            // nothing else, the same as a tap anywhere outside it. The card
            // stays in the tree either way, so an expanded card does not fold
            // when its menu opens.
            child: NexTapGuarded(
              controller: _guard,
              // Brief acknowledgment only; keeping the card at 98%
              // for the whole menu session alters its layout and golden UI.
              child: AnimatedScale(
                scale: _ducking ? 0.98 : 1.0,
                duration: NexMotion.fast,
                onEnd: () {
                  if (mounted && _ducking) {
                    setState(() => _ducking = false);
                  }
                },
                child: child!,
              ),
            ),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
