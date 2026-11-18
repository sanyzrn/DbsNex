import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';

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
      } else {
        final now = DateTime.now();
        final today = DateUtils.dateOnly(now);
        final day = await nexPickModuleDate(
          context,
          initial: widget.initial.isBefore(today) ? today : widget.initial,
          first: today,
          last: DateTime(now.year + 3, 12, 31),
        );
        if (day == null || !mounted) return;
        final time = await nexPickModuleTime(
          context,
          initial: const TimeOfDay(hour: 9, minute: 0),
        );
        if (time == null || !mounted) return;
        final at = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        final fa = NexModuleStrings.persian(context);
        final wording = nexReadableDate(
          widget.initial,
          solar: true,
          persian: fa,
        );
        final ok = await widget.store.setReminder(
          key,
          sourceKind: 'fund',
          sourceId: widget.fundId,
          at: at,
          title: widget.body,
          body: '${widget.body} · $wording',
        );
        if (!ok) throw StateError('Reminder unavailable');
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
              '${nexReadableDate(at, solar: true, persian: fa)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
            ),
          Wrap(
            spacing: NexSpacing.sm,
            children: [
              TextButton(
                onPressed: busy || !widget.store.remindersEnabled
                    ? null
                    : () => change(clear: false),
                child: Text(fundStrings(context, 'reminderSet')),
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
