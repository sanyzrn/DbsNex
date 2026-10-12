part of '../cycle_screen.dart';

/// Editing or deleting a logged period. Split out of cycle_screen.dart
/// (REL-10).
extension _CycleEditPeriod on _CycleScreenState {
  Future<void> _editPeriod(CyclePeriod period) async {
    final l10n = AppLocalizations.of(context);
    var start = period.start.local;
    DateTime? end = period.end?.local;
    final result = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => CycleTheme(
          child: AlertDialog(
            title: Text(l10n.cycleEditPeriod),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.cycleStart),
                  trailing: Text(cycleDayMonth(context, start, solar: _solar)),
                  onTap: () async {
                    final picked = await _pickPastDay(initial: start);
                    if (picked != null) setDialog(() => start = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.cycleEnd),
                  trailing: Text(
                    end == null
                        ? l10n.cycleOngoing
                        : cycleDayMonth(context, end!, solar: _solar),
                  ),
                  onTap: () async {
                    final picked = await _pickPastDay(
                      initial: end ?? start,
                      first: start,
                    );
                    if (picked != null) setDialog(() => end = picked);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(l10n.cycleDeletePeriod),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'save'),
                child: Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == 'delete') {
      await _services.cycleDeletePeriod(period.id);
    } else if (result == 'save') {
      // Said, not silently stored (DATA-10): overlapping periods would skew
      // every prediction counted from them.
      final from = CycleDate.of(start);
      final to = end == null ? null : CycleDate.of(end!);
      if (CyclePeriod.clash(_periods, period.id, from, to) != null) {
        if (mounted) nexShowBanner(context, message: l10n.cyclePeriodOverlap);
        return;
      }
      await _services.cycleUpdatePeriod(period.id, start, end);
    } else {
      return;
    }
    await _changed();
  }
}
