import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_strings.dart';

/// The same three destinations on each screen; a page transition preserves
/// the purchase draft instead of rebuilding it when another tool is opened.
class GoldWorkspace extends StatelessWidget {
  const GoldWorkspace({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => NexAdaptiveSegments<int>(
    segments: [
      ButtonSegment(
        value: 0,
        label: Text(goldStrings(context, 'workspaceBuy')),
        icon: const Icon(Icons.shopping_bag_outlined),
      ),
      ButtonSegment(
        value: 1,
        label: Text(goldStrings(context, 'workspaceSell')),
        icon: const Icon(Icons.sell_outlined),
      ),
      ButtonSegment(
        value: 2,
        label: Text(goldStrings(context, 'workspaceMelt')),
        icon: const Icon(Icons.balance_outlined),
      ),
    ],
    selected: {selected},
    onSelectionChanged: (values) => onChanged(values.first),
  );
}
