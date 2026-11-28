import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

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
