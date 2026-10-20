import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

/// A habit's optional daily nudge: one switch and a time. It rings at that
/// time every day until it is turned off, the habit is archived or deleted,
/// or the module is removed; the notification says only that a habit is
/// waiting, never which.
class HabitReminderTile extends StatefulWidget {
  const HabitReminderTile({
    super.key,
    required this.store,
    required this.habitId,
  });

  final NexModuleStore store;
  final String habitId;

  @override
  State<HabitReminderTile> createState() => _HabitReminderTileState();
}

class _HabitReminderTileState extends State<HabitReminderTile> {
  TimeOfDay? _time;
  bool _busy = false;

  String get _key => 'habit:${widget.habitId}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final body = await widget.store.get('__reminder', _key);
    if (!mounted) return;
    final at = body == null ? null : DateTime.tryParse('${body['at']}');
    setState(
      () => _time = at == null || body?['repeat'] != 'daily'
          ? null
          : TimeOfDay.fromDateTime(at.toLocal()),
    );
  }

  Future<void> _set(TimeOfDay time) async {
    if (_busy) return;
    setState(() => _busy = true);
    final strings = habitsStrings;
    try {
      final now = DateTime.now();
      final ok = await widget.store.setDailyReminder(
        _key,
        sourceKind: 'habit',
        sourceId: widget.habitId,
        at: DateTime(now.year, now.month, now.day, time.hour, time.minute),
        title: strings(context, 'reminderTitle'),
        body: strings(context, 'reminderBody'),
      );
      if (!mounted) return;
      if (!ok) {
        nexShowBanner(
          context,
          message: strings(context, 'reminderFailed'),
          kind: NexBannerKind.failed,
        );
      }
      await _load();
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: strings(context, 'reminderFailed'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.clearReminder(_key);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final picked = await nexPickModuleTime(
      context,
      initial: _time ?? const TimeOfDay(hour: 20, minute: 0),
    );
    if (picked != null && mounted) await _set(picked);
  }

  String _label(TimeOfDay time) {
    final text =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    return NexModuleStrings.persian(context)
        ? text.replaceAllMapped(
            RegExp('[0-9]'),
            (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
          )
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final time = _time;
    return NexPanel(
      icon: Icons.notifications_none,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey('habit-reminder-time'),
              onTap: _busy ? null : () => unawaited(_pick()),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings(context, 'dailyReminder'),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      time == null
                          ? strings(context, 'reminderOff')
                          : strings(context, 'reminderAt', {
                              'time': _label(time),
                            }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Switch(
            key: const ValueKey('habit-reminder-switch'),
            value: time != null,
            onChanged: _busy
                ? null
                : (on) => unawaited(on ? _pick() : _clear()),
          ),
        ],
      ),
    );
  }
}
