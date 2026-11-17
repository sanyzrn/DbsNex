import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_fields.dart';
import 'medicine_money.dart';
import 'medicine_parse.dart';
import 'medicine_repository.dart';
import 'medicine_strings.dart';

/// One place the medicine was found: where, what it cost in tomans, and
/// the day. All three are the person's own record — the module suggests no
/// pharmacy and fetches no price.
class MedicinePlaceSheet extends StatefulWidget {
  const MedicinePlaceSheet({
    super.key,
    required this.store,
    required this.medicineId,
  });

  final NexModuleStore store;
  final String medicineId;

  @override
  State<MedicinePlaceSheet> createState() => _MedicinePlaceSheetState();
}

class _MedicinePlaceSheetState extends State<MedicinePlaceSheet> {
  final _place = TextEditingController();
  final _price = TextEditingController();
  final _day = TextEditingController();
  bool _busy = false;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _day.text =
        '${today.year}/${MedicineFields.two(today.month)}/'
        '${MedicineFields.two(today.day)}';
  }

  @override
  void dispose() {
    _place.dispose();
    _price.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final day = MedicineParse.day(_day.text);
    final price = MedicineMoney.parse(_price.text);
    final badPrice = _price.text.trim().isNotEmpty && price == null;
    if (_place.text.trim().isEmpty ||
        day == null ||
        day == MedicineParse.invalid ||
        badPrice) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await MedicineRepository.addSource(
        widget.store,
        widget.medicineId,
        place: _place.text,
        priceRials: price,
        at: day,
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
    final price = MedicineMoney.parse(_price.text);
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
                strings(context, 'addPlace'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.md),
              MedicineFields.line(
                fieldKey: const ValueKey('medicine-place-name'),
                controller: _place,
                label: strings(context, 'place'),
                hint: strings(context, 'placeHint'),
                helper: _showErrors && _place.text.trim().isEmpty
                    ? strings(context, 'placeRequired')
                    : strings(context, 'placeNote'),
              ),
              const SizedBox(height: NexSpacing.sm),
              MedicineFields.number(
                fieldKey: const ValueKey('medicine-place-price'),
                controller: _price,
                label: strings(context, 'price'),
                hint: strings(context, 'priceHint'),
                helper:
                    _showErrors &&
                        _price.text.trim().isNotEmpty &&
                        price == null
                    ? strings(context, 'badPrice')
                    : price == null
                    ? strings(context, 'priceNote')
                    : medicineStrings(context, 'priceShown', {
                        'price': MedicineMoney.tomanText(context, price),
                      }),
              ),
              const SizedBox(height: NexSpacing.sm),
              NexModuleDateEntry(
                controller: _day,
                child: MedicineFields.line(
                  fieldKey: const ValueKey('medicine-place-day'),
                  controller: _day,
                  label: strings(context, 'day'),
                  hint: strings(context, 'dateHint'),
                  keyboard: TextInputType.datetime,
                  helper:
                      _showErrors &&
                          (_day.text.trim().isEmpty ||
                              MedicineParse.day(_day.text) ==
                                  MedicineParse.invalid ||
                              MedicineParse.day(_day.text) == null)
                      ? strings(context, 'badDate')
                      : null,
                ),
              ),
              const SizedBox(height: NexSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('medicine-place-save'),
                  onPressed: _busy ? null : _save,
                  child: Text(strings(context, 'savePlace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
