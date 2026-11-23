import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_fields.dart';
import 'parking_alarm.dart';
import 'parking_logic.dart';
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
    this.minutes,
  });

  final NexModuleStore store;
  final String recordId;
  final DateTime expiresAt;
  final String place;
  final String floor;

  /// How many minutes before the end the reminder rings, when one is set
  /// (2.8.4); null when there is none.
  final int? minutes;

  Future<void> _open(BuildContext context) async {
    final now = DateTime.now();
    final current = minutes;
    // Reopening a reminder starts on what is set, not on a silent ten; a
    // short stay gets the longest lead that still fits.
    final initial =
        current != null && ParkingLogic.reminderFits(expiresAt, current, now)
        ? current
        : ParkingLogic.suggestedReminderMinutes(expiresAt, now);
    final set = await nexShowSheet<bool>(
      context: context,
      builder: (_) => ParkingReminderSheet(
        store: store,
        recordId: recordId,
        expiresAt: expiresAt,
        place: place,
        floor: floor,
        initialMinutes: initial,
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
        // What is set says so, and only what is set can be cleared (2.8.4).
        TextButton.icon(
          key: const ValueKey('parking-quick-remind'),
          onPressed: () => unawaited(_open(context)),
          icon: Icon(
            minutes == null
                ? Icons.notifications_none_outlined
                : Icons.notifications_active,
          ),
          label: Text(
            minutes == null
                ? strings(context, 'quickRemind')
                : strings(context, 'quickReminderSet', {'minutes': minutes!}),
          ),
        ),
        if (minutes != null)
          TextButton(
            key: const ValueKey('parking-quick-remind-clear'),
            onPressed: () => unawaited(ParkingAlarm.disarm(store, recordId)),
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
    this.initialMinutes,
  });

  final NexModuleStore store;
  final String recordId;
  final DateTime expiresAt;
  final String place;
  final String floor;

  /// The lead the sheet opens on: what is already set, or a suggestion that
  /// fits the time left. Null only for a caller with no fitting lead.
  final int? initialMinutes;

  @override
  State<ParkingReminderSheet> createState() => _ParkingReminderSheetState();
}

class _ParkingReminderSheetState extends State<ParkingReminderSheet> {
  late final _minutes = TextEditingController(
    text: '${widget.initialMinutes ?? 10}',
  );
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
      final ok = await ParkingAlarm.arm(
        context,
        widget.store,
        widget.recordId,
        expiresAt: widget.expiresAt,
        minutes: minutes,
        place: widget.place,
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
                    // A choice whose moment has already passed would only
                    // produce an error after saving; it is not offered.
                    onSelected:
                        ParkingLogic.reminderFits(
                          widget.expiresAt,
                          choice,
                          DateTime.now(),
                        )
                        ? (_) {
                            setState(() {
                              _minutes.text = '$choice';
                              _error = null;
                            });
                          }
                        : null,
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
