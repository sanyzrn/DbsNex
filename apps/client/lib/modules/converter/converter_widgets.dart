import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_format.dart';

/// The small pieces all three tabs share: a typed date with the app's own
/// calendar picker beside it, a dropdown that is drawn like every other field
/// in Nex, and the quiet notes under a result.

/// A date typed as `year/month/day`, with the calendar picker's button on the
/// same row — the same arrangement the rest of the app uses for a date.
class ConverterDateField extends StatelessWidget {
  const ConverterDateField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onPick,
    this.errorText,
    this.fieldKey,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onPick;
  final String? errorText;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            keyboardType: TextInputType.datetime,
            // A date is a number: it reads left to right even in a Persian
            // screen, and the digits themselves are whatever was typed.
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: converterText(context, 'dateFieldLabel'),
              hintText: converterText(context, 'dateFieldHint'),
              errorText: errorText,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NexSpacing.xs,
            top: 4,
          ),
          child: IconButton(
            tooltip: converterText(context, 'pickDay'),
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => unawaited(onPick()),
          ),
        ),
      ],
    );
  }
}

/// A field that chooses one value. Drawn with the theme's own input
/// decoration — so it has the resting, focus and error outline every other
/// field has — and with the shared dropdown corners and surface.
class ConverterDropdown extends StatelessWidget {
  const ConverterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: nexDropdownRadius,
          dropdownColor: nexDropdownColor(context),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A quiet line under a result: what the number is based on, what a chart
/// does differently, that a lunar date is calculated.
class ConverterNote extends StatelessWidget {
  const ConverterNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: NexSpacing.sm,
        start: NexSpacing.xs,
        end: NexSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 16, color: colour),
          const SizedBox(width: NexSpacing.xs + 2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of a list that pairs a name with a value — a calendar and its
/// date, a size system and its size.
class ConverterInfoRow extends StatelessWidget {
  const ConverterInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasised
                  ? theme.textTheme.titleMedium?.copyWith(
                      color: nexModuleAccent(context, 'converter'),
                    )
                  : theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
