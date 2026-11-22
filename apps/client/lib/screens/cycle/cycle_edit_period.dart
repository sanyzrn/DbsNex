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
    final changed = await nexShowSheet<bool>(
      context: context,
      builder: (_) => CycleSheet(
        child: _PeriodEditSheet(
          services: _services,
          period: period,
          periods: _periods,
          today: _today,
          solar: _solar,
        ),
      ),
    );
    if (changed == true && mounted) await _changed();
  }
}

class _PeriodEditSheet extends StatefulWidget {
  const _PeriodEditSheet({
    required this.services,
    required this.period,
    required this.periods,
    required this.today,
    required this.solar,
  });

  final NexServices services;
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
  bool _busy = false;

  Future<void> _pickStart() async {
    final latest = widget.today;
    final initial = _start.isAfter(latest) ? latest : _start;
    final cutoff = CycleDate.of(latest).addDays(-400).local;
    final first = initial.isBefore(cutoff)
        ? CycleDate.of(initial).addDays(-365).local
        : cutoff;
    final picked = await nexPickDate(
      context,
      initial: initial,
      first: first,
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

  Future<void> _save() async {
    final from = CycleDate.of(_start);
    final to = _end == null ? null : CycleDate.of(_end!);
    final l10n = AppLocalizations.of(context);
    if (CyclePeriod.clash(widget.periods, widget.period.id, from, to) != null) {
      setState(() => _error = l10n.cyclePeriodOverlap);
      return;
    }
    await _write(() async {
      try {
        await widget.services.cycleUpdatePeriod(widget.period.id, _start, _end);
      } catch (_) {
        final latest = await widget.services.cyclePeriods();
        if (mounted &&
            CyclePeriod.clash(latest, widget.period.id, from, to) != null) {
          setState(() => _error = l10n.cyclePeriodOverlap);
          return false;
        }
        rethrow;
      }
      return true;
    });
  }

  Future<void> _write(Future<bool> Function() save) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await save();
      if (saved && mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.cycleWriteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    await _write(() async {
      await widget.services.cycleDeletePeriod(widget.period.id);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _end == null
        ? null
        : CycleDate.of(_end!).daysSince(CycleDate.of(_start)) + 1;
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
              onTap: _busy ? null : _pickStart,
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
              onTap: _busy ? null : _pickEnd,
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
              onPressed: _busy ? null : _save,
              child: Text(l10n.save),
            ),
            const SizedBox(height: NexSpacing.xs),
            TextButton.icon(
              key: const ValueKey('cycle-edit-delete'),
              onPressed: _busy ? null : _delete,
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
