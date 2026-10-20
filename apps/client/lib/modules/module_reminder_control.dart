import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_time_picker.dart';
import 'module_dates.dart';
import 'nex_module_store.dart';

class NexModuleReminderControl extends StatefulWidget {
  const NexModuleReminderControl({
    super.key,
    required this.store,
    required this.sourceKind,
    required this.sourceId,
    this.body,
    this.initial,
  });
  final NexModuleStore store;
  final String sourceKind, sourceId;

  /// What the notification says. Without it, a neutral line that names
  /// nothing from the record.
  final String? body;

  /// The day the date picker opens on, when the record has one that matters
  /// (a loan's due date).
  final DateTime? initial;
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
    try {
      final now = DateTime.now();
      final suggested = widget.initial;
      final date = await nexPickModuleDate(
        context,
        initial:
            suggested != null && !suggested.isBefore(DateUtils.dateOnly(now))
            ? suggested
            : now,
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
        body:
            widget.body ??
            (fa
                ? 'موعدی که تنظیم کرده‌اید رسیده است؛ نکس را باز کنید.'
                : 'Your chosen reminder is due. Open Nex.'),
      );
      if (!mounted) return;
      nexShowBanner(
        context,
        message: ok
            ? (fa ? 'یادآوری تنظیم شد.' : 'Reminder set.')
            : (fa
                  ? 'یادآوری تنظیم نشد؛ زمان آینده و مجوز اعلان را بررسی کنید.'
                  : 'Reminder was not set. Check the future time and notification permission.'),
        kind: ok ? NexBannerKind.done : NexBannerKind.failed,
      );
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: fa
              ? 'ذخیرهٔ یادآوری ناموفق بود؛ دوباره تلاش کنید.'
              : 'Could not save the reminder. Retry.',
          kind: NexBannerKind.failed,
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
                  try {
                    await widget.store.clearReminder(reminderKey);
                  } catch (_) {
                    if (context.mounted) {
                      nexShowBanner(
                        context,
                        message: fa
                            ? 'حذف یادآوری ناموفق بود.'
                            : 'Could not clear the reminder.',
                        kind: NexBannerKind.failed,
                      );
                    }
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
