part of 'medicine_widgets.dart';

class MedicineNumberFields extends StatelessWidget {
  const MedicineNumberFields({
    super.key,
    required this.quantity,
    required this.doseUnits,
    required this.refill,
    required this.expiry,
    required this.showErrors,
  });

  final TextEditingController quantity;
  final TextEditingController doseUnits;
  final TextEditingController refill;
  final TextEditingController expiry;
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final badNumber = strings(context, 'badNumber');

    String? helper(String written, String good, String bad, int minimum) {
      if (showErrors && written.trim().isNotEmpty) {
        final parsed = MedicineParse.count(written);
        if (parsed == null || parsed < minimum) {
          return badNumber;
        }
      }
      return good;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicineFields.number(
          fieldKey: const ValueKey('medicine-field-quantity'),
          controller: quantity,
          label: strings(context, 'quantity'),
          hint: strings(context, 'quantityHint'),
          helper: helper(
            quantity.text,
            strings(context, 'quantityNote'),
            badNumber,
            0,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        MedicineFields.number(
          fieldKey: const ValueKey('medicine-field-dose-units'),
          controller: doseUnits,
          label: strings(context, 'doseUnits'),
          hint: strings(context, 'doseUnitsHint'),
          helper: helper(
            doseUnits.text,
            strings(context, 'doseUnitsNote'),
            badNumber,
            1,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        MedicineFields.number(
          fieldKey: const ValueKey('medicine-field-refill'),
          controller: refill,
          label: strings(context, 'refill'),
          hint: strings(context, 'quantityHint'),
          helper: helper(
            refill.text,
            strings(context, 'refillNote'),
            badNumber,
            0,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexModuleDateEntry(
          controller: expiry,
          child: MedicineFields.line(
            fieldKey: const ValueKey('medicine-field-expiry'),
            keyboard: TextInputType.datetime,
            hint: strings(context, 'dateHint'),
            controller: expiry,
            label: strings(context, 'expiry'),
            // A half-typed or impossible date says so in its own words —
            // not with the number fields' message.
            helper:
                showErrors &&
                    MedicineParse.expiry(expiry.text) == MedicineParse.invalid
                ? strings(context, 'badDate')
                : strings(context, 'expiryNote'),
          ),
        ),
      ],
    );
  }
}

/// The routine times as chips, one deletable each.
class MedicineTimeChips extends StatelessWidget {
  const MedicineTimeChips({super.key, required this.times, this.onRemoved});

  final List<String> times;
  final ValueChanged<String>? onRemoved;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
    child: Wrap(
      spacing: NexSpacing.sm,
      runSpacing: NexSpacing.xs,
      children: [
        for (final time in times)
          InputChip(
            key: ValueKey('medicine-time-$time'),
            label: Text(MedicineFields.digits(context, time)),
            onDeleted: onRemoved == null ? null : () => onRemoved!(time),
          ),
      ],
    ),
  );
}
