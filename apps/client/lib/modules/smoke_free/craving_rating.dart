import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

class CravingRating extends StatelessWidget {
  const CravingRating({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.optional = true,
  });
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool optional;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: NexSpacing.sm),
      NexAdaptiveSegments<int>(
        segments: [
          if (optional)
            ButtonSegment(
              value: 0,
              label: Text(smokeFreeStrings(context, 'notRated')),
            ),
          for (final n in [1, 2, 3])
            ButtonSegment(
              value: n,
              label: Text(
                smokeFreeStrings(
                  context,
                  n == 1
                      ? 'intensityLow'
                      : n == 2
                      ? 'intensityMedium'
                      : 'intensityHigh',
                ),
              ),
            ),
        ],
        selected: {value ?? 0},
        onSelectionChanged: (values) =>
            onChanged(values.first == 0 ? null : values.first),
      ),
    ],
  );
}
