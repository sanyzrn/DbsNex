import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/nex_time_picker.dart';
import 'module_dates.dart';
import 'nex_module_store.dart';

class NexModuleReminderControl extends StatefulWidget {
  const NexModuleReminderControl({
    super.key,
    required this.store,
    required this.sourceKind,
    required this.sourceId,
  });
  final NexModuleStore store;
  final String sourceKind, sourceId;
  @override
  State<NexModuleReminderControl> createState() =>
      _NexModuleReminderControlState();
}

class _NexModuleReminderControlState extends State<NexModuleReminderControl> {
  bool _busy = false;
  String get reminderKey => '${widget.sourceKind}:${widget.sourceId}';
  Future<void> _set() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final date = await nexPickModuleDate(
        context,
        initial: now,
        first: DateUtils.dateOnly(now),
        last: DateTime(now.year + 2, now.month, now.day),
      );
      if (date == null || !mounted) return;
      final time = await nexPickTime(
        context,
        initial: TimeOfDay.fromDateTime(now),
      );
      if (time == null || !mounted) return;
      final ok = await widget.store.setReminder(
        reminderKey,
        sourceKind: widget.sourceKind,
        sourceId: widget.sourceId,
        at: DateTime(date.year, date.month, date.day, time.hour, time.minute),
        title: l10n.cycleNotifyTitle,
        body: fa
            ? 'موعدی که تنظیم کرده‌اید رسیده است؛ نکس را باز کنید.'
            : 'Your chosen reminder is due. Open Nex.',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (fa ? 'یادآوری تنظیم شد.' : 'Reminder set.')
                : (fa
                      ? 'یادآوری تنظیم نشد؛ زمان آینده و مجوز اعلان را بررسی کنید.'
                      : 'Reminder was not set. Check the future time and notification permission.'),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              fa
                  ? 'ذخیرهٔ یادآوری ناموفق بود؛ دوباره تلاش کنید.'
                  : 'Could not save the reminder. Retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return Wrap(
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _set,
          icon: const Icon(Icons.notifications_outlined),
          label: Text(l10n.remindPick),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await widget.store.clearReminder(reminderKey);
                  } catch (_) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          (fa
                              ? 'حذف یادآوری ناموفق بود.'
                              : 'Could not clear the reminder.'),
                        ),
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(l10n.remindClear),
        ),
      ],
    );
  }
}
