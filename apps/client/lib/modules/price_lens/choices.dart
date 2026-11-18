import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// Shared segments also own their wrapping variant. A long unit catalogue
/// uses that variant on wide screens instead of squeezing a dozen labels.
class LensChoices<T> extends StatelessWidget {
  const LensChoices({
    super.key,
    required this.values,
    required this.value,
    required this.label,
    required this.onChanged,
    this.keyFor,
  });
  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;
  final Key Function(T)? keyFor;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: values.length > 4 ? 359 : double.infinity,
      ),
      child: NexAdaptiveSegments<T>(
        segments: [
          for (final v in values)
            ButtonSegment(
              value: v,
              label: Text(label(v), key: keyFor?.call(v)),
            ),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (v) => onChanged!(v.first),
      ),
    ),
  );
}
