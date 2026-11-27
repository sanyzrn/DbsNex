import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_fields.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_money.dart';
import 'medicine_schedule.dart';
import 'medicine_strings.dart';
import 'medicine_widgets.dart';

/// The pieces the cabinet shows around a medicine: its routine and how
/// long the stock lasts, its boxes and their days, and where it was found.
/// Every line is built from something the person wrote — nothing here
/// knows a dose, an interaction or a pharmacy.

/// The weekday's name in the reader's language, numbered as Dart does
/// (Monday 1 … Sunday 7).
String medicineWeekdayName(BuildContext context, int weekday) =>
    medicineStrings(context, switch (weekday) {
      1 => 'weekday1',
      2 => 'weekday2',
      3 => 'weekday3',
      4 => 'weekday4',
      5 => 'weekday5',
      6 => 'weekday6',
      _ => 'weekday7',
    });

/// The week in the order the reader expects: Saturday first in Persian,
/// Monday first in English.
List<int> medicineWeekdayOrder(BuildContext context) =>
    NexModuleStrings.persian(context)
    ? const [6, 7, 1, 2, 3, 4, 5]
    : const [1, 2, 3, 4, 5, 6, 7];

/// The days of the week as choices, each a chip that can be switched on
/// and off. No day chosen means every day.
class MedicineWeekdayPicker extends StatelessWidget {
  const MedicineWeekdayPicker({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: NexSpacing.sm,
    runSpacing: NexSpacing.xs,
    children: [
      for (final day in medicineWeekdayOrder(context))
        FilterChip(
          key: ValueKey('medicine-day-$day'),
          label: Text(medicineWeekdayName(context, day)),
          selected: selected.contains(day),
          onSelected: (_) => onToggle(day),
        ),
    ],
  );
}

/// The routine as the person reads it back, on the medicine's own sheet:
/// its times, the days it covers, the dates it runs between, and — when
/// their own numbers allow the arithmetic — about how long the stock
/// lasts and whether it is time to look for more.
class MedicineScheduleSection extends StatelessWidget {
  const MedicineScheduleSection({
    super.key,
    required this.body,
    required this.days,
  });

  final Map<String, Object?> body;

  /// The person's free-text "days" note from before the schedule was
  /// structured, kept and shown exactly as they wrote it.
  final String days;

  @override
  Widget build(BuildContext context) {
    final schedule = MedicineSchedule.of(body);
    if (!schedule.isWritten && days.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final strings = medicineStrings;
    final week = schedule.weekdays
        .map((day) => medicineWeekdayName(context, day))
        .join('، ');
    final quantity = MedicineModels.readCount(body, 'quantity');
    final doseUnits = MedicineModels.readCount(body, 'doseUnits');
    final warnDays = MedicineModels.readWarnDays(body);
    final daysLeft = MedicineLogic.runsOutInDays(
      quantity: quantity,
      doseUnits: doseUnits,
      schedule: schedule,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicineLabel(strings(context, 'scheduleLabel')),
        if (schedule.times.isNotEmpty)
          Text(
            schedule.times
                .map((time) => MedicineFields.digits(context, time))
                .join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
        if (week.isNotEmpty) Text(week, style: theme.textTheme.bodyMedium),
        if (schedule.times.isEmpty && week.isEmpty && days.isNotEmpty)
          Text(days, style: theme.textTheme.bodyMedium),
        if (schedule.everyDays != null)
          Text(
            medicineStrings(context, 'everyNDays', {
              'count': schedule.everyDays,
            }),
            style: theme.textTheme.bodyMedium,
          ),
        // Both day rules written: the weekday set is the one the routine
        // reads (README → Decisions). The person is told, not left to
        // wonder why the every-N-days line seems to change nothing.
        if (schedule.weekdays.isNotEmpty && schedule.everyDays != null)
          Text(
            medicineStrings(context, 'bothDaysNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (schedule.startsOn != null || schedule.endsOn != null)
          Text(
            [
              if (schedule.startsOn != null)
                '${strings(context, 'startsOn')}: '
                    '${nexModuleDateLabel(context, schedule.startsOn!)}',
              if (schedule.endsOn != null)
                '${strings(context, 'endsOn')}: '
                    '${nexModuleDateLabel(context, schedule.endsOn!)}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
        if (days.isNotEmpty && (schedule.times.isNotEmpty || week.isNotEmpty))
          Text(days, style: theme.textTheme.bodySmall),
        if (schedule.times.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'timesNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (daysLeft != null)
          Text(
            daysLeft == 0
                ? strings(context, 'runsOutToday')
                : medicineStrings(context, 'runsOutIn', {'count': daysLeft}),
            style: theme.textTheme.bodyMedium,
          ),
        if (MedicineLogic.runoutWarning(daysLeft, warnDays))
          Text(
            strings(context, 'startLooking'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}

/// Every box the person recorded for one medicine, with the day each one
/// expires, and the one action that adds another.
class MedicineBoxSection extends StatelessWidget {
  const MedicineBoxSection({
    super.key,
    required this.boxes,
    required this.onAdd,
    required this.onDelete,
  });

  final List<ModuleRecord> boxes;
  final VoidCallback onAdd;
  final void Function(ModuleRecord box) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = medicineStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings(context, 'boxes'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('medicine-add-box'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'addBox')),
            ),
          ],
        ),
        if (boxes.isEmpty)
          Text(
            strings(context, 'noBoxes'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final box in boxes)
            MedicineBoxRow(box: box, onDelete: () => onDelete(box)),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}

/// One box: the day it expires and, when written, how many units it holds.
class MedicineBoxRow extends StatelessWidget {
  const MedicineBoxRow({super.key, required this.box, this.onDelete});

  final ModuleRecord box;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = MedicineModels.readDay(box.body, 'expiresAt');
    final units = MedicineModels.readCount(box.body, 'units');
    final state = expiresAt == null
        ? null
        : MedicineLogic.expiryOf(expiresAt, DateTime.now());
    return ListTile(
      key: ValueKey('medicine-box-${box.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.inventory_2_outlined,
        color: state?.expired == true
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        expiresAt == null
            ? medicineStrings(context, 'noRecord')
            : medicineStrings(context, 'boxExpiry', {
                'date': nexModuleDateLabel(context, expiresAt),
              }),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: state?.expired == true ? theme.colorScheme.error : null,
        ),
      ),
      subtitle: units == null
          ? null
          : Text(medicineStrings(context, 'boxUnits', {'count': units})),
      trailing: IconButton(
        key: ValueKey('medicine-box-delete-${box.id}'),
        tooltip: AppLocalizations.of(context).delete,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

/// Where the medicine was found: the small log the brief asks for, so the
/// next search starts somewhere.
class MedicinePlaceSection extends StatelessWidget {
  const MedicinePlaceSection({
    super.key,
    required this.sources,
    required this.onAdd,
    required this.onDelete,
  });

  final List<ModuleRecord> sources;
  final VoidCallback onAdd;
  final void Function(ModuleRecord source) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = medicineStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings(context, 'places'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('medicine-add-place'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'addPlace')),
            ),
          ],
        ),
        if (sources.isEmpty)
          Text(
            strings(context, 'noPlaces'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final source in sources)
            MedicinePlaceRow(source: source, onDelete: () => onDelete(source)),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}

/// One recorded place: where, how much, and the day it was bought.
class MedicinePlaceRow extends StatelessWidget {
  const MedicinePlaceRow({super.key, required this.source, this.onDelete});

  final ModuleRecord source;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = MedicineModels.readString(source.body, 'place');
    final price = MedicineModels.readPriceRial(source.body);
    final at = MedicineModels.readDay(source.body, 'at');
    return ListTile(
      key: ValueKey('medicine-place-${source.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.storefront_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        place.isEmpty ? medicineStrings(context, 'noRecord') : place,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        [
          if (price != null)
            medicineStrings(context, 'priceShown', {
              'price': MedicineMoney.tomanText(context, price),
            }),
          if (at != null)
            medicineStrings(context, 'boughtOn', {
              'date': nexModuleDateLabel(context, at),
            }),
        ].join(' · '),
      ),
      trailing: IconButton(
        key: ValueKey('medicine-place-delete-${source.id}'),
        tooltip: AppLocalizations.of(context).delete,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
