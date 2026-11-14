import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_format.dart';
import 'converter_size_tables.dart';
import 'converter_sizes.dart';
import 'converter_strings.dart';
import 'converter_widgets.dart';

/// The Sizes tab: a chart, the system whose number you have, and the size —
/// with the body measurement that number stands for written beside it, and
/// every other system's number for the same body.
class ConverterSizesView extends StatelessWidget {
  const ConverterSizesView({
    super.key,
    required this.chart,
    required this.system,
    required this.rowIndex,
    required this.onChart,
    required this.onSystem,
    required this.onRow,
  });

  final SizeChart chart;
  final SizeSystem system;
  final int rowIndex;
  final ValueChanged<String> onChart;
  final ValueChanged<String> onSystem;
  final ValueChanged<int> onRow;

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    // A row without a number in this system cannot be chosen, so the field
    // always points at one that can.
    final rows = [
      for (var index = 0; index < chart.rows.length; index++)
        if (chart.rows[index].sizeIn(system.id) != null) index,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final selected = rows.contains(rowIndex) ? rowIndex : rows.first;
    final row = chart.rows[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexPanel(
          title: strings(context, 'chartLabel'),
          icon: _iconFor(chart.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConverterDropdown(
                key: const ValueKey('converter-chart'),
                label: strings(context, 'chartLabel'),
                value: chart.id,
                items: [
                  for (final value in converterSizeCharts)
                    DropdownMenuItem<String>(
                      value: value.id,
                      child: Text(
                        strings(context, value.titleKey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onChart(value);
                },
              ),
              const SizedBox(height: NexSpacing.sm),
              ConverterDropdown(
                key: const ValueKey('converter-size-system'),
                label: strings(context, 'sizeSystemLabel'),
                value: system.id,
                items: [
                  for (final value in chart.systems)
                    DropdownMenuItem<String>(
                      value: value.id,
                      child: Text(
                        strings(context, value.labelKey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSystem(value);
                },
              ),
              const SizedBox(height: NexSpacing.sm),
              ConverterDropdown(
                key: const ValueKey('converter-size'),
                label: strings(context, 'sizeLabel'),
                value: '$selected',
                items: [
                  for (final index in rows)
                    DropdownMenuItem<String>(
                      value: '$index',
                      child: Text(
                        _sizeItem(context, chart.rows[index], system),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  final index = int.tryParse(value ?? '');
                  if (index != null) onRow(index);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        NexPanel(
          title: strings(context, 'sizeAllSystems'),
          icon: Icons.straighten,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final value in chart.systems)
                ConverterInfoRow(
                  label: strings(context, value.labelKey),
                  value: converterSizeText(
                    context,
                    row.sizeIn(value.id) ?? '—',
                  ),
                  emphasised: value.id == system.id,
                ),
              if (row.measures.isNotEmpty)
                Divider(
                  height: NexSpacing.lg,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              for (final measure in row.measures)
                ConverterInfoRow(
                  label: converterMeasureName(context, measure.key),
                  value: converterMeasureText(context, measure),
                ),
            ],
          ),
        ),
        ConverterNote(text: strings(context, 'sizeNote')),
      ],
    );
  }

  /// «۳۸ · ۸۸ سانتیمتر» — the size and the measurement it stands for, so no
  /// number appears on its own.
  String _sizeItem(BuildContext context, SizeRow row, SizeSystem system) {
    final size = converterSizeText(context, row.sizeIn(system.id) ?? '—');
    if (row.measures.isEmpty) return size;
    return '$size · ${converterMeasureText(context, row.measures.first)}';
  }

  IconData _iconFor(String chartId) => switch (chartId) {
    'womenShoes' || 'menShoes' || 'childrenShoes' => Icons.directions_walk,
    'rings' => Icons.circle_outlined,
    _ => Icons.checkroom_outlined,
  };
}
