part of '../cycle_screen.dart';

/// Editing or deleting a logged period. Split out of cycle_screen.dart
/// (REL-10).
///
/// A sheet rather than a dialog: the dates are two pickers and a
/// confirmation, and a dialog that closes the moment a date is chosen cannot
/// say "these dates overlap another period" without losing the correction
/// that was already made. Here the clash is said beside the dates, the sheet
/// stays open, and nothing is written until both are free.
extension _CycleEditPeriod on _CycleScreenState {
  Future<void> _editPeriod(CyclePeriod period) async {
    final result = await nexShowSheet<_PeriodEdit>(
      context: context,
      builder: (_) => CycleSheet(
        child: _PeriodEditSheet(
          period: period,
          periods: _periods,
          today: _today,
          solar: _solar,
        ),
      ),
    );
    if (result == null) return;
    if (result.delete) {
      await _services.cycleDeletePeriod(period.id);
    } else {
      await _services.cycleUpdatePeriod(period.id, result.start, result.end);
    }
    await _changed();
  }
}

typedef _PeriodEdit = ({bool delete, DateTime start, DateTime? end});

class _PeriodEditSheet extends StatefulWidget {
  const _PeriodEditSheet({
    required this.period,
    required this.periods,
    required this.today,
    required this.solar,
  });

  final CyclePeriod period;
  final List<CyclePeriod> periods;
  final DateTime today;
  final bool solar;

  @override
  State<_PeriodEditSheet> createState() => _PeriodEditSheetState();
}

class _PeriodEditSheetState extends State<_PeriodEditSheet> {
  late DateTime _start = widget.period.start.local;
  late DateTime? _end = widget.period.end?.local;
  String? _error;

  Future<void> _pickStart() async {
    final picked = await nexPickDate(
      context,
      initial: _start,
      first: widget.today.subtract(const Duration(days: 400)),
      last: widget.today,
      solar: widget.solar,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked;
      // An end before the new start is not a period; carry it along.
      if (_end != null && _end!.isBefore(picked)) _end = picked;
      _error = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await nexPickDate(
      context,
      initial: _end ?? _start,
      first: _start,
      last: widget.today,
      solar: widget.solar,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _end = picked;
      _error = null;
    });
  }

  void _save() {
    final from = CycleDate.of(_start);
    final to = _end == null ? null : CycleDate.of(_end!);
    if (CyclePeriod.clash(widget.periods, widget.period.id, from, to) != null) {
      setState(() => _error = AppLocalizations.of(context).cyclePeriodOverlap);
      return;
    }
    Navigator.pop<_PeriodEdit>(context, (
      delete: false,
      start: _start,
      end: _end,
    ));
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await nexShowDialog<bool>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(l10n.cycleDeletePeriod),
        content: NexDialogBody(child: Text(l10n.cycleDeletePeriodConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('cycle-edit-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop<_PeriodEdit>(context, (
      delete: true,
      start: _start,
      end: _end,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _end == null ? null : _end!.difference(_start).inDays + 1;
    return NexSheetBody(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.cycleEditPeriod, style: theme.textTheme.titleLarge),
            const SizedBox(height: NexSpacing.sm),
            ListTile(
              key: const ValueKey('cycle-edit-start'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.event_outlined,
                color: cyclePeriodColor(theme.brightness),
              ),
              title: Text(l10n.cycleStart),
              trailing: Text(
                cycleDayMonth(context, _start, solar: widget.solar),
                style: theme.textTheme.bodyLarge,
              ),
              onTap: _pickStart,
            ),
            ListTile(
              key: const ValueKey('cycle-edit-end'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.event_available_outlined,
                color: cyclePeriodColor(theme.brightness),
              ),
              title: Text(l10n.cycleEnd),
              trailing: Text(
                _end == null
                    ? l10n.cycleOngoing
                    : cycleDayMonth(context, _end!, solar: widget.solar),
                style: theme.textTheme.bodyLarge,
              ),
              onTap: _pickEnd,
            ),
            if (days != null)
              Text(
                l10n.cycleDays(days),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: NexSpacing.xs),
              Text(
                _error!,
                key: const ValueKey('cycle-edit-error'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            FilledButton(
              key: const ValueKey('cycle-edit-save'),
              onPressed: _save,
              child: Text(l10n.save),
            ),
            const SizedBox(height: NexSpacing.xs),
            TextButton.icon(
              key: const ValueKey('cycle-edit-delete'),
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.cycleDeletePeriod),
            ),
          ],
        ),
      ),
    );
  }
}
