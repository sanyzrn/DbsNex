import 'dart:async';
import 'editor_checkpoint.dart';
import 'warranty_repository.dart';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'nex_text_field.dart';
import 'warranty_fields.dart';
import 'warranty_logic.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';

part 'warranty_widgets_more.dart';

/// The rows and sections of the warranties screen, kept apart so the
/// screen file stays about flow and storage. Every date shown is
/// Gregorian, in the interface's digits; nothing is scheduled.

/// A section of the list: heading and rows under it.
class WarrantySection extends StatelessWidget {
  const WarrantySection({
    super.key,
    required this.icon,
    required this.title,
    required this.records,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final List<ModuleRecord> records;
  final void Function(ModuleRecord) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      NexShelfHeading(icon: icon, title: title),
      const SizedBox(height: NexSpacing.sm),
      for (final record in records)
        WarrantyRow(
          key: ValueKey('warranty-row-${record.id}'),
          record: record,
          onOpen: () => onOpen(record),
        ),
      const SizedBox(height: NexSpacing.md),
    ],
  );
}

/// One purchase in the list: the product big enough to read, the brand
/// beside it, and the days its coverage has left — or the days since it
/// ended.
class WarrantyRow extends StatelessWidget {
  const WarrantyRow({super.key, required this.record, required this.onOpen});

  final ModuleRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = record.body;
    final product = WarrantyModels.readString(body, 'product');
    final brand = WarrantyModels.readString(body, 'brand');
    final end = WarrantyModels.readDate(body, 'coverageEnd');
    final status = end == null
        ? (expired: true, expiring: false, daysLeft: 0)
        : WarrantyLogic.statusOf(end, DateTime.now());

    final days = end == null
        ? strings(context, 'unknownDate')
        : status.expired
        ? (status.daysLeft == 0
              ? strings(context, 'endsToday')
              : strings(context, 'expiredDaysAgo', {'count': -status.daysLeft}))
        : status.daysLeft == 0
        ? strings(context, 'endsToday')
        : status.daysLeft == 1
        ? strings(context, 'oneDayLeft')
        : strings(context, 'daysLeft', {'count': status.daysLeft});

    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: ListTile(
        onTap: onOpen,
        leading: NexIconTile(
          status.expired
              ? Icons.event_busy_outlined
              : status.expiring
              ? Icons.schedule_outlined
              : Icons.verified_outlined,
          color:
              (status.expired
                      ? NexHue.slate
                      : status.expiring
                      ? NexHue.amber
                      : NexHue.teal)
                  .of(theme.brightness),
        ),
        title: Text(
          product,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle:
            [
              if (brand.isNotEmpty) brand,
              if (end != null) WarrantyDateText(end: end),
              if (end != null)
                Text(
                  days,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.expired
                        ? scheme.onSurfaceVariant
                        : status.expiring
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ].isEmpty
            ? null
            : Wrap(
                spacing: NexSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (end != null) WarrantyDateText(end: end),
                  Text(
                    days,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.expiring && !status.expired
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One archived purchase, one tap from coming back.
class WarrantyArchivedRow extends StatelessWidget {
  const WarrantyArchivedRow({
    super.key,
    required this.record,
    required this.onUnarchive,
    required this.onOpen,
  });

  final ModuleRecord record;
  final VoidCallback onUnarchive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onOpen,
    leading: NexIconTile(
      Icons.inventory_2_outlined,
      color: NexHue.slate.of(Theme.of(context).brightness),
    ),
    title: Text(
      WarrantyModels.readString(record.body, 'product'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    trailing: TextButton(
      key: ValueKey('warranty-unarchive-${record.id}'),
      onPressed: onUnarchive,
      child: Text(warrantyStrings(context, 'unarchive')),
    ),
  );
}

/// A Gregorian date in the interface's digits, marked as such by the
/// module's words elsewhere.
class WarrantyDateText extends StatelessWidget {
  const WarrantyDateText({super.key, required this.end});

  final DateTime end;

  @override
  Widget build(BuildContext context) => Text(
    warrantyStrings(context, 'ymd', {
      'y': end.year,
      'm': warrantyTwoDigits(end.month),
      'd': warrantyTwoDigits(end.day),
    }),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// Two digits with a leading zero, as a string the strings map can fill.
String warrantyTwoDigits(int value) => value < 10 ? '0$value' : '$value';

/// The small sheet a claim or service note is written in: the person's
/// own words, dated on save. No outcome is presumed.
