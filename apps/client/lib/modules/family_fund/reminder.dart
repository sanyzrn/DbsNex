import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'fund_text.dart';
import 'strings.dart';

/// The line a fund reminder carries under its title, in the page's language.
/// It names the day and the clock time that were actually chosen — the
/// earlier version said the suggested day even after the manager picked
/// another one.
String fundReminderBody(String title, DateTime at, {required bool persian}) =>
    '$title${fundSepFor(persian: persian)}'
    '${nexReadableDate(at, solar: true, persian: persian, time: true)}';

/// Both alerts refer to the same real fund row. The kit control derives its
/// key from the source, so using it twice would overwrite the first alert.
class FundReminder extends StatefulWidget {
  const FundReminder({
    super.key,
    required this.store,
    required this.reminderKind,
    required this.fundId,
    required this.initial,
    required this.body,
  });
  final NexModuleStore store;
  final String reminderKind, fundId, body;
  final DateTime initial;
  @override
  State<FundReminder> createState() => _FundReminderState();
}

class _FundReminderState extends State<FundReminder> {
  String get key => '${widget.reminderKind}:${widget.fundId}';
  bool busy = false;
  late Future<Map<String, Object?>?> reminder = widget.store.get(
    '__reminder',
    key,
  );

  Future<void> change({required bool clear}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (clear) {
        await widget.store.clearReminder(key);
        if (mounted) {
          nexShowBanner(
            context,
            message: fundStrings(context, 'reminderRemoved'),
          );
        }
      } else {
        final stored = await widget.store.get('__reminder', key);
        if (!mounted) return;
        final storedAt = DateTime.tryParse('${stored?['at']}')?.toLocal();
        final now = DateTime.now();
        final today = DateUtils.dateOnly(now);
        final suggested = storedAt ?? widget.initial;
        final day = await nexPickModuleDate(
          context,
          initial: suggested.isBefore(today) ? today : suggested,
          first: today,
          last: DateTime(now.year + 3, 12, 31),
        );
        if (day == null || !mounted) return;
        final time = await nexPickModuleTime(
          context,
          initial: storedAt == null
              ? const TimeOfDay(hour: 9, minute: 0)
              : TimeOfDay.fromDateTime(storedAt),
        );
        if (time == null || !mounted) return;
        final at = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        final persian = NexModuleStrings.persian(context);
        final ok = await widget.store.setReminder(
          key,
          sourceKind: 'fund',
          sourceId: widget.fundId,
          at: at,
          title: widget.body,
          body: fundReminderBody(widget.body, at, persian: persian),
        );
        if (!ok) throw StateError('Reminder unavailable');
        if (mounted) {
          nexShowBanner(
            context,
            message: fundStrings(context, 'reminderSetFor', {
              'date': nexReadableDate(
                at,
                solar: true,
                persian: persian,
                time: true,
              ),
            }),
          );
        }
      }
    } on Object {
      if (mounted) {
        nexShowBanner(
          context,
          message: fundStrings(context, 'reminderError'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          reminder = widget.store.get('__reminder', key);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>?>(
    future: reminder,
    builder: (context, snapshot) {
      final fa = NexModuleStrings.persian(context);
      final at = DateTime.tryParse('${snapshot.data?['at']}')?.toLocal();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (at != null)
            Text(
              fundStrings(context, 'reminderRings', {
                'date': nexReadableDate(
                  at,
                  solar: true,
                  persian: fa,
                  time: true,
                ),
              }),
            ),
          Wrap(
            spacing: NexSpacing.sm,
            children: [
              TextButton(
                onPressed: busy || !widget.store.remindersEnabled
                    ? null
                    : () => change(clear: false),
                child: Text(
                  fundStrings(
                    context,
                    at == null ? 'reminderSet' : 'reminderChange',
                  ),
                ),
              ),
              if (at != null)
                TextButton(
                  onPressed: busy ? null : () => change(clear: true),
                  child: Text(fundStrings(context, 'reminderClear')),
                ),
            ],
          ),
          if (!widget.store.remindersEnabled)
            Text(fundStrings(context, 'reminderUnavailable')),
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(() {
                reminder = widget.store.get('__reminder', key);
              }),
              child: Text(fundStrings(context, 'retry')),
            ),
        ],
      );
    },
  );
}
