import 'package:flutter/material.dart';
import '../tokens/nex_tokens.dart';

enum NexSwipeAction { delete, addTag }
typedef NexSwipeActionResolver = NexSwipeAction Function({required bool isLeading});

class SwipeableNoteCard extends StatefulWidget {
  const SwipeableNoteCard({
    super.key,
    required this.child,
    required this.resolveAction,
    required this.onDelete,
    required this.onAddTag,
    required this.deleteLabel,
    required this.addTagLabel,
  });
  final Widget child;
  final NexSwipeActionResolver resolveAction;
  final VoidCallback onDelete;
  final VoidCallback onAddTag;
  final String deleteLabel;
  final String addTagLabel;
  @override
  State<SwipeableNoteCard> createState() => _SwipeableNoteCardState();
}

class _SwipeableNoteCardState extends State<SwipeableNoteCard> {
  double dx = 0;
  bool get rtl => Directionality.of(context) == TextDirection.rtl;
  String label(NexSwipeAction action) =>
      action == NexSwipeAction.delete ? widget.deleteLabel : widget.addTagLabel;
  void run(NexSwipeAction action) =>
      action == NexSwipeAction.delete ? widget.onDelete() : widget.onAddTag();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final open = constraints.maxWidth * 0.45;
    final leading = widget.resolveAction(isLeading: true);
    final trailing = widget.resolveAction(isLeading: false);
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: widget.deleteLabel): widget.onDelete,
        CustomSemanticsAction(label: widget.addTagLabel): widget.onAddTag,
      },
      child: GestureDetector(
        onLongPress: () async {
          final selected = await showMenu<NexSwipeAction>(
            context: context,
            position: const RelativeRect.fromLTRB(24, 160, 24, 0),
            items: [
              PopupMenuItem(value: leading, child: Text(label(leading))),
              PopupMenuItem(value: trailing, child: Text(label(trailing))),
            ],
          );
          if (selected != null) run(selected);
        },
        onHorizontalDragUpdate: (value) =>
            setState(() => dx = (dx + value.delta.dx).clamp(-open, open)),
        onHorizontalDragEnd: (_) {
          final threshold = constraints.maxWidth * nexSwipeThreshold;
          if (dx.abs() < threshold) return setState(() => dx = 0);
          final logicalLeading = rtl ? dx < 0 : dx > 0;
          setState(() => dx = logicalLeading
              ? (rtl ? -open : open)
              : (rtl ? open : -open));
        },
        child: Transform.translate(offset: Offset(dx, 0), child: widget.child),
      ),
    );
  });
}