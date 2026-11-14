import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_format.dart';
import 'converter_strings.dart';
import 'converter_units.dart';
import 'converter_widgets.dart';

/// The Units tab: pick a category, say which unit you have and which you
/// want, and type. The answer follows every keystroke — there is no Convert
/// button, because there is nothing to confirm.
class ConverterUnitsView extends StatelessWidget {
  const ConverterUnitsView({
    super.key,
    required this.category,
    required this.fromId,
    required this.toId,
    required this.controller,
    required this.errorText,
    required this.onCategory,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
    required this.onChanged,
  });

  final UnitCategory category;
  final String fromId;
  final String toId;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<UnitCategory> onCategory;
  final ValueChanged<String> onFrom;
  final ValueChanged<String> onTo;
  final VoidCallback onSwap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final units = converterUnitsIn(category);
    return NexPanel(
      icon: _iconFor(category),
      title: strings(context, _categoryKey(category)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final value in UnitCategory.values)
                ChoiceChip(
                  key: ValueKey('converter-category-${value.name}'),
                  label: Text(strings(context, _categoryKey(value))),
                  selected: value == category,
                  onSelected: (_) => onCategory(value),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConverterDropdown(
                  key: const ValueKey('converter-from'),
                  label: strings(context, 'fromLabel'),
                  value: fromId,
                  items: _items(context, units),
                  onChanged: (value) {
                    if (value != null) onFrom(value);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: NexSpacing.xs,
                ),
                child: IconButton(
                  key: const ValueKey('converter-swap'),
                  tooltip: strings(context, 'swapLabel'),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: onSwap,
                ),
              ),
              Expanded(
                child: ConverterDropdown(
                  key: const ValueKey('converter-to'),
                  label: strings(context, 'toLabel'),
                  value: toId,
                  items: _items(context, units),
                  onChanged: (value) {
                    if (value != null) onTo(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          TextField(
            key: const ValueKey('converter-value'),
            controller: controller,
            onChanged: onChanged,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            // A quantity is a number: left to right in both languages, while
            // the digits around it follow the reader.
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: strings(context, 'valueLabel'),
              errorText: errorText,
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _items(
    BuildContext context,
    List<ConverterUnit> units,
  ) => [
    for (final unit in units)
      DropdownMenuItem<String>(
        value: unit.id,
        child: Text(
          converterUnitLabel(context, unit),
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];

  IconData _iconFor(UnitCategory category) => switch (category) {
    UnitCategory.length => Icons.straighten,
    UnitCategory.mass => Icons.scale_outlined,
    UnitCategory.volume => Icons.water_drop_outlined,
    UnitCategory.temperature => Icons.thermostat,
    UnitCategory.area => Icons.square_foot,
    UnitCategory.speed => Icons.speed,
  };
}

String _categoryKey(UnitCategory category) => switch (category) {
  UnitCategory.length => 'catLength',
  UnitCategory.mass => 'catMass',
  UnitCategory.volume => 'catVolume',
  UnitCategory.temperature => 'catTemperature',
  UnitCategory.area => 'catArea',
  UnitCategory.speed => 'catSpeed',
};
