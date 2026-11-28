import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The frame a [InputDecoration] draws around a field, without the
/// [InputDecorator] that would break the engine.
///
/// Super Editor's viewport and its selection overlay are *slotted* render
/// objects, and `InputDecorator` is one too: a slotted child nested inside a
/// slotted parent lands in the wrong slot and the layout throws. The frame that
/// matters — the hint, the fill, the outline and the padding — is small enough
/// to draw here, and fields that need a label, an error line, a counter or an
/// icon keep the platform field instead (see [NexTextField]).
class NexFieldFrame extends StatelessWidget {
  const NexFieldFrame({
    super.key,
    required this.decoration,
    required this.isEmpty,
    required this.isEnabled,
    required this.child,
  });

  final InputDecoration decoration;
  final bool isEmpty;
  final bool isEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = decoration.enabledBorder is OutlineInputBorder
        ? (decoration.enabledBorder! as OutlineInputBorder).borderSide
        : (decoration.border is OutlineInputBorder
              ? (decoration.border! as OutlineInputBorder).borderSide
              : BorderSide.none);
    final radius = decoration.border is OutlineInputBorder
        ? (decoration.border! as OutlineInputBorder).borderRadius
        : const BorderRadius.all(Radius.circular(NexRadius.sm));
    final fill = decoration.fillColor;
    final padding =
        decoration.contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: NexSpacing.xs,
          vertical: NexSpacing.xs,
        );
    final text = decoration.hintText;
    final hintStyle =
        decoration.hintStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: decoration.filled == true ? fill : null,
        borderRadius: radius,
        border: side == BorderSide.none
            ? null
            : Border.all(
                color: isEnabled ? side.color : theme.disabledColor,
                width: side.width,
              ),
      ),
      child: Padding(
        padding: padding,
        child: text == null || !isEmpty
            ? child
            : Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          text,
                          style: hintStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
      ),
    );
  }
}

enum NexFormatCommand { bold, italic, mono, strikethrough, quote, link, clear }

/// The seven commands a selection offers, in a bar above it.
///
/// Super Editor draws its own selection UI, so the platform's context menu is
/// not part of the engine; this is the same set of commands, in the app's own
/// colours, acting on the controller through `NexTextFormatting`.
class NexSelectionFormatBar extends StatelessWidget {
  const NexSelectionFormatBar({
    super.key,
    required this.labels,
    required this.onSelected,
  });

  final Map<NexFormatCommand, String> labels;
  final ValueChanged<NexFormatCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(NexRadius.sm),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.xs),
        // Seven commands do not fit a phone: the bar scrolls sideways rather
        // than pushing the last ones off the field.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in labels.entries)
                TextButton(
                  onPressed: () => onSelected(entry.key),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.xs,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
