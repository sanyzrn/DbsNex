import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// Segments become wrapping, full-height choices on compact/large-text forms.
class AdaptiveSegments<T> extends StatelessWidget {
  const AdaptiveSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
  });
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= 360 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20) {
        return SegmentedButton<T>(
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
        );
      }
      return Wrap(
        spacing: NexSpacing.sm,
        runSpacing: NexSpacing.sm,
        children: [
          for (final segment in segments)
            ChoiceChip(
              label: segment.label ?? const SizedBox(),
              avatar: segment.icon,
              selected: selected.contains(segment.value),
              onSelected: onSelectionChanged == null || !segment.enabled
                  ? null
                  : (_) => onSelectionChanged!({segment.value}),
            ),
        ],
      );
    },
  );
}
