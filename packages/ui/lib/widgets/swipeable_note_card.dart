import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// Closed set of two swipe actions (ADR-022) — not an open framework.
enum NexSwipeAction {
  delete,
  addTag,
}

typedef NexSwipeActionResolver = NexSwipeAction Function({required bool isLeading});

/// Timeline card swipe reveal: Delete (warning red) / Add Tag (neutral).
///
/// Per mockup `.card-wrap`: overflow clipped, reveal only while this card is
/// open, one open card at a time. Tap the revealed action to execute it.
class SwipeableNoteCard extends StatefulWidget {
  const SwipeableNoteCard({
    super.key,
    required this.child,
    required this.resolveAction,
    required this.onDelete,
    required this.onAddTag,
    this.openCardId,
    this.cardId,
    this.onOpenChanged,
  });

  final Widget child;
  final NexSwipeActionResolver resolveAction;
  final VoidCallback onDelete;
  final VoidCallback onAddTag;
  final String? openCardId;
  final String? cardId;
  final ValueChanged<String?>? onOpenChanged;

  @override
  State<SwipeableNoteCard> createState() => _SwipeableNoteCardState();
}

class _SwipeableNoteCardState extends State<SwipeableNoteCard>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _controller;

  bool get _isOpen => _dx.abs() > 0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void didUpdateWidget(covariant SwipeableNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Close when another card becomes the open one.
    if (widget.openCardId != null &&
        widget.openCardId != widget.cardId &&
        _dx != 0) {
      _animateTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final start = _dx;
    final anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _controller.forward(from: 0).whenComplete(() {
      anim.removeListener(listener);
      if (target == 0) {
        if (widget.openCardId == widget.cardId) {
          widget.onOpenChanged?.call(null);
        }
      } else if (widget.cardId != null) {
        widget.onOpenChanged?.call(widget.cardId);
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dx = (_dx + d.delta.dx).clamp(-160.0, 160.0));
    if (widget.cardId != null && widget.openCardId != widget.cardId) {
      widget.onOpenChanged?.call(widget.cardId);
    }
  }

  void _onDragEnd(DragEndDetails d, double width) {
    final threshold = width * nexSwipeThreshold;
    if (_dx.abs() < threshold) {
      _animateTo(0);
      return;
    }
    final openingLeading = _dx > 0;
    _animateTo(openingLeading ? width * 0.45 : -width * 0.45);
  }

  void _run(NexSwipeAction action) {
    if (action == NexSwipeAction.delete) {
      widget.onDelete();
    } else {
      widget.onAddTag();
    }
    _animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Horizontal padding lives outside the clip so reveal never bleeds
      // between neighboring cards (mockup .card-wrap).
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.xs + 1,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final leading = widget.resolveAction(isLeading: true);
          final trailing = widget.resolveAction(isLeading: false);
          return ClipRRect(
            borderRadius: BorderRadius.circular(NexColors.cardRadius),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                if (_isOpen)
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: _RevealPanel(
                            action: leading,
                            alignEnd: false,
                            neutralBg: theme.colorScheme.surfaceContainerHighest,
                            onTap: () => _run(leading),
                          ),
                        ),
                        Expanded(
                          child: _RevealPanel(
                            action: trailing,
                            alignEnd: true,
                            neutralBg: theme.colorScheme.surfaceContainerHighest,
                            onTap: () => _run(trailing),
                          ),
                        ),
                      ],
                    ),
                  ),
                Transform.translate(
                  offset: Offset(_dx, 0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: (d) => _onDragEnd(d, width),
                    onTap: _isOpen ? () => _animateTo(0) : null,
                    child: Material(
                      color: theme.colorScheme.surface,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RevealPanel extends StatelessWidget {
  const _RevealPanel({
    required this.action,
    required this.alignEnd,
    required this.neutralBg,
    required this.onTap,
  });

  final NexSwipeAction action;
  final bool alignEnd;
  final Color neutralBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDelete = action == NexSwipeAction.delete;
    final bg = isDelete ? NexColors.swipeDelete : neutralBg;
    final fg = isDelete ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDelete ? Icons.delete_outline : Icons.label_outline,
                color: fg,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                isDelete ? 'Delete' : 'Add Tag',
                style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
