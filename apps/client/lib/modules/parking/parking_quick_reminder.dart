import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_fields.dart';
import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_strings.dart';

/// The quick reminder a paid parking offers: some minutes before the written
/// end, ten by default and editable. It is an explicit, opt-in device alert
/// through the store's own reminder call, so the platform applies its
/// permission checks and cancels it with the record.
///
/// A parking with no paid time still offers the platform's free-time control;
/// this one exists because a meter has an end to count back from.
class ParkingQuickReminder extends StatelessWidget {
  const ParkingQuickReminder({
    super.key,
    required this.store,
    required this.recordId,
    required this.expiresAt,
    required this.place,
    required this.floor,
  });

  final NexModuleStore store;
  final String recordId;
  final DateTime expiresAt;
  final String place;
  final String floor;

  Future<void> _open(BuildContext context) async {
    final set = await nexShowSheet<bool>(
      context: context,
      builder: (_) => ParkingReminderSheet(
        store: store,
        recordId: recordId,
        expiresAt: expiresAt,
        place: place,
        floor: floor,
      ),
    );
    if (set == true && context.mounted) {
      NexBannerHost.of(context)?.show(
        kind: NexBannerKind.done,
        message: parkingStrings(context, 'reminderSaved'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = parkingStrings;
    return Wrap(
      spacing: NexSpacing.sm,
      children: [
        TextButton.icon(
          key: const ValueKey('parking-quick-remind'),
          onPressed: () => unawaited(_open(context)),
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(strings(context, 'quickRemind')),
        ),
        TextButton(
          key: const ValueKey('parking-quick-remind-clear'),
          onPressed: () => unawaited(
            store.clearReminder('${ParkingModels.session}:$recordId'),
          ),
          child: Text(AppLocalizations.of(context).remindClear),
        ),
      ],
    );
  }
}

/// The small form behind the quick reminder: how many minutes before the end
/// the alert should ring, with the four usual choices a thumb can reach.
class ParkingReminderSheet extends StatefulWidget {
  const ParkingReminderSheet({
    super.key,
    required this.store,
    required this.recordId,
    required this.expiresAt,
    required this.place,
    required this.floor,
  });

  final NexModuleStore store;
  final String recordId;
  final DateTime expiresAt;
  final String place;
  final String floor;

  @override
  State<ParkingReminderSheet> createState() => _ParkingReminderSheetState();
}

class _ParkingReminderSheetState extends State<ParkingReminderSheet> {
  final _minutes = TextEditingController(text: '10');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  int? get _value {
    final text = LocalValue.digits(_minutes.text.trim());
    final value = int.tryParse(text);
    return value == null || value < 1 || value > 720 ? null : value;
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final minutes = _value;
    final now = DateTime.now();
    if (minutes == null) {
      setState(() => _error = parkingStrings(context, 'reminderBad'));
      return;
    }
    if (!ParkingLogic.reminderFits(widget.expiresAt, minutes, now)) {
      setState(() => _error = parkingStrings(context, 'reminderPast'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final where = widget.place.trim().isEmpty
          ? parkingStrings(context, 'detailsTitle')
          : widget.place.trim();
      final at = ParkingLogic.reminderAt(widget.expiresAt, minutes);
      final ok = await widget.store.setReminder(
        '${ParkingModels.session}:${widget.recordId}',
        sourceKind: ParkingModels.session,
        sourceId: widget.recordId,
        at: at,
        title: AppLocalizations.of(context).cycleNotifyTitle,
        body: parkingStrings(context, 'reminderBody', {'place': where}),
      );
      if (!mounted) {
        return;
      }
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = parkingStrings(context, 'reminderNotSet');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = parkingStrings(context, 'reminderBad');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = parkingStrings;
    final theme = Theme.of(context);
    final minutes = _value;
    final at = minutes == null
        ? null
        : ParkingLogic.reminderAt(widget.expiresAt, minutes);

    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        top: NexSpacing.md,
        bottom: NexSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings(context, 'reminderSheetTitle'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            Wrap(
              spacing: NexSpacing.sm,
              children: [
                for (final choice in const [5, 10, 15, 30])
                  ChoiceChip(
                    key: ValueKey('parking-remind-$choice'),
                    label: Text(ParkingFields.digits(context, '$choice')),
                    selected: _minutes.text.trim() == '$choice',
                    onSelected: (_) {
                      setState(() {
                        _minutes.text = '$choice';
                        _error = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            ParkingFields.line(
              fieldKey: const ValueKey('parking-remind-minutes'),
              controller: _minutes,
              label: strings(context, 'reminderMinutes'),
              keyboard: TextInputType.number,
              helper: _error,
              onChanged: (_) => setState(() => _error = null),
            ),
            if (at != null)
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.xs),
                child: Text(
                  strings(context, 'reminderAt', {
                    'time': ParkingFields.hm(context, at.toLocal()),
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: NexSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('parking-remind-save'),
                onPressed: _busy ? null : _save,
                child: Text(strings(context, 'quickRemind')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Digits typed on a Persian keyboard read as plain digits. A tiny local
/// copy of the app's helper, because `packages/core` is not exported to
/// modules.
class LocalValue {
  const LocalValue._();

  static String digits(String text) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final p = persian.indexOf(char);
      final a = arabic.indexOf(char);
      if (p >= 0) {
        buffer.write(p);
      } else if (a >= 0) {
        buffer.write(a);
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
}
