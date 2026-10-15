import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_fields.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_parse.dart';
import 'medicine_strings.dart';

part 'medicine_widgets_more.dart';

/// The rows the medicine detail sheet is made of, kept apart so the sheet
/// file stays about flow and storage. Nothing here knows anything
/// medical: a row shows what was written, no more.

/// One logged dose in the history.
class MedicineDoseRow extends StatelessWidget {
  const MedicineDoseRow({super.key, required this.dose, this.onDelete});

  final ModuleRecord dose;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = MedicineModels.readDate(dose.body, 'at')?.toLocal();
    final knownAction = const [
      'taken',
      'skipped',
    ].contains(dose.body['action']);
    final taken =
        MedicineModels.readString(dose.body, 'action') == MedicineModels.taken;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        taken ? Icons.check_circle_outline : Icons.remove_circle_outline,
        color: taken
            ? NexHue.teal.of(theme.brightness)
            : NexHue.slate.of(theme.brightness),
      ),
      title: Text(
        medicineStrings(
          context,
          !knownAction
              ? 'unknownLog'
              : dose.body['stockLimited'] == true
              ? 'takenLimited'
              : taken
              ? 'taken'
              : 'skipped',
        ),
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: at == null
          ? null
          : Text(
              medicineStrings(context, 'loggedAt', {
                'date': MedicineFields.ymd(context, at),
                'time': MedicineFields.hm(context, at),
              }),
            ),
      trailing: IconButton(
        key: ValueKey('medicine-dose-delete-${dose.id}'),
        tooltip: AppLocalizations.of(context).delete,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

/// A small label above a block of the sheet.
class MedicineLabel extends StatelessWidget {
  const MedicineLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One state mark: red when [on], quiet otherwise.
class MedicineMark extends StatelessWidget {
  const MedicineMark(this.text, {super.key, required this.on});

  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: on ? scheme.error : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// The middle of the medicine detail sheet: the states worth reading on
/// opening — stock, expiry — and everything the person wrote. Reads the
/// body itself, so the sheet stays about flow and storage.
class MedicineInfoSection extends StatelessWidget {
  const MedicineInfoSection({super.key, required this.body});

  final Map<String, Object?> body;

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strength = MedicineModels.readString(body, 'strength');
    final packageUnit = MedicineModels.readString(body, 'package');
    final instructions = MedicineModels.readString(body, 'instructions');
    final purpose = MedicineModels.readString(body, 'purpose');
    final days = MedicineModels.readString(body, 'days');
    final times = MedicineModels.readTimes(body);
    final quantity = MedicineModels.readCount(body, 'quantity');
    final doseUnits = MedicineModels.readCount(body, 'doseUnits');
    final expiresAt = MedicineModels.readDate(body, 'expiresAt');
    final expiry = MedicineLogic.expiryOf(expiresAt, DateTime.now());
    final refillThreshold = MedicineModels.readCount(body, 'refillThreshold');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            if (quantity != null)
              MedicineMark(
                strings(context, 'quantityLeft', {
                  'count': quantity,
                  'unit': packageUnit.isEmpty ? strength : packageUnit,
                }),
                on:
                    quantity == 0 ||
                    MedicineLogic.needsRefill(quantity, refillThreshold),
              ),
            if (expiresAt != null)
              MedicineMark(
                expiry.expired
                    ? strings(context, 'expired')
                    : expiry.soon
                    ? strings(context, 'expiringSoon')
                    : strings(context, 'expiryLabel'),
                on: expiry.expired,
              ),
          ],
        ),
        const SizedBox(height: NexSpacing.md),
        if (expiresAt != null) ...[
          MedicineLabel(strings(context, 'expiryLabel')),
          Text(MedicineFields.ymd(context, expiresAt)),
          const SizedBox(height: NexSpacing.md),
        ],
        if (instructions.isNotEmpty) ...[
          MedicineLabel(strings(context, 'instructionsLabel')),
          Text(instructions, style: theme.textTheme.bodyMedium),
          const SizedBox(height: NexSpacing.md),
        ],
        if (times.isNotEmpty || days.isNotEmpty) ...[
          MedicineLabel(strings(context, 'timesLabel')),
          Text(
            [
              if (times.isNotEmpty)
                times.map((t) => MedicineFields.digits(context, t)).join(' · '),
              if (days.isNotEmpty) days,
            ].join(' — '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'timesNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        if (purpose.isNotEmpty) ...[
          MedicineLabel(strings(context, 'purposeLabel')),
          Text(purpose, style: theme.textTheme.bodyMedium),
          const SizedBox(height: NexSpacing.md),
        ],
        if (quantity != null && doseUnits != null && doseUnits > 0)
          Text(
            strings(context, 'doseUnitsNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The dose history block of the detail sheet: what was logged, when,
/// and the correction beside each entry.
class MedicineHistorySection extends StatelessWidget {
  const MedicineHistorySection({
    super.key,
    required this.doses,
    required this.onDelete,
  });

  final List<ModuleRecord> doses;

  /// Deleting a log is a correction: stock the log took comes back.
  final void Function(ModuleRecord dose) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          medicineStrings(context, 'doseHistory'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        if (doses.isEmpty)
          Text(
            medicineStrings(context, 'noDoses'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final dose in doses)
            MedicineDoseRow(dose: dose, onDelete: () => onDelete(dose)),
      ],
    );
  }
}

/// The number fields of the medicine editor: quantity, units per dose,
/// refill threshold and expiry date. The error helpers appear only after
/// a failed save, and an empty field is never an error — it means the
/// person keeps that number themselves.
