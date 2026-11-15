import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_fields.dart';
import 'warranty_strings.dart';

/// The one-time alert, offered at the moment the purchase is saved and its
/// end date is on screen — not hidden in the purchase's own page.
///
/// A new purchase offers it on; a saved one starts off and says so, because
/// the module cannot read back whether a reminder is already set and must
/// not claim to have removed one.
class WarrantyReminderOffer extends StatelessWidget {
  const WarrantyReminderOffer({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.moment,
    required this.choices,
    required this.selectedDays,
    required this.onDays,
    this.refreshing = false,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// The moment the alert will ring, already computed for the chosen lead
  /// time.
  final DateTime moment;

  /// The lead times still in the future, largest first.
  final List<int> choices;
  final int? selectedDays;
  final ValueChanged<int> onDays;

  /// True when the purchase already existed, so the note explains that an
  /// earlier reminder is not being changed.
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notifications_outlined, color: scheme.primary),
                  const SizedBox(width: NexSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings(context, 'reminderTitle'),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          strings(
                            context,
                            refreshing
                                ? 'reminderExistingNote'
                                : 'reminderOfferNote',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Switch(
                    key: const ValueKey('warranty-remind-switch'),
                    value: enabled,
                    onChanged: onChanged,
                  ),
                ],
              ),
              if (enabled) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(
                  strings(context, 'reminderLeadLabel'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.xs),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  children: [
                    for (final days in choices)
                      ChoiceChip(
                        key: ValueKey('warranty-remind-$days'),
                        label: Text(
                          days == 1
                              ? strings(context, 'reminderOneDay')
                              : strings(context, 'reminderDays', {
                                  'count': days,
                                }),
                        ),
                        selected: selectedDays == days,
                        onSelected: (_) => onDays(days),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  strings(context, 'reminderAt', {
                    'date': WarrantyFields.dayLabel(context, moment),
                  }),
                  key: const ValueKey('warranty-remind-at'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
