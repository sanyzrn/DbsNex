import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_fields.dart';
import 'medicine_parse.dart';
import 'medicine_repository.dart';
import 'medicine_strings.dart';

/// One box of one medicine: the day it expires and, if the person counts
/// it, how many units are inside. The day is theirs to type or pick on
/// the shared calendar; nothing is suggested.
class MedicineBoxSheet extends StatefulWidget {
  const MedicineBoxSheet({
    super.key,
    required this.store,
    required this.medicineId,
  });

  final NexModuleStore store;
  final String medicineId;

  @override
  State<MedicineBoxSheet> createState() => _MedicineBoxSheetState();
}

class _MedicineBoxSheetState extends State<MedicineBoxSheet> {
  final _expiry = TextEditingController();
  final _units = TextEditingController();
  bool _busy = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _expiry.dispose();
    _units.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final expiry = MedicineParse.day(_expiry.text);
    final units = MedicineParse.count(_units.text);
    final badUnits =
        _units.text.trim().isNotEmpty && (units == null || units < 0);
    if (expiry == null || expiry == MedicineParse.invalid || badUnits) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await MedicineRepository.addBox(
        widget.store,
        widget.medicineId,
        expiresAt: expiry,
        units: units,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: medicineStrings(context, 'saveFailed'),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final expiry = MedicineParse.day(_expiry.text);
    return PopScope(
      canPop: !_busy,
      child: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings(context, 'addBox'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.md),
              NexModuleDateEntry(
                controller: _expiry,
                child: MedicineFields.line(
                  fieldKey: const ValueKey('medicine-box-expiry'),
                  controller: _expiry,
                  label: strings(context, 'expiry'),
                  hint: strings(context, 'dateHint'),
                  keyboard: TextInputType.datetime,
                  helper: _showErrors && expiry == null
                      ? strings(context, 'badDate')
                      : _showErrors && expiry == MedicineParse.invalid
                      ? strings(context, 'badDate')
                      : null,
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              MedicineFields.number(
                fieldKey: const ValueKey('medicine-box-units'),
                controller: _units,
                label: strings(context, 'boxUnitsLabel'),
                hint: strings(context, 'quantityHint'),
                helper:
                    _showErrors &&
                        _units.text.trim().isNotEmpty &&
                        (_units.text.trim().isEmpty ||
                            MedicineParse.count(_units.text) == null)
                    ? strings(context, 'badNumber')
                    : strings(context, 'boxUnitsNote'),
              ),
              const SizedBox(height: NexSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('medicine-box-save'),
                  onPressed: _busy ? null : _save,
                  child: Text(strings(context, 'saveBox')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
