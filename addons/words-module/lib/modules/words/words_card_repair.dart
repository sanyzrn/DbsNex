part of 'words_card_page.dart';

extension _WordsDateRepair on _WordsCardPageState {
  Future<void> _repairDue() async {
    if (_saving || _restoring || widget.card == null) return;
    _repairPaint(() => _saving = true);
    try {
      final yes = await nexShowDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(wordsStrings(ctx, 'scheduleUnknown')),
          content: NexDialogBody(
            child: Text(wordsStrings(ctx, 'repairDueBody')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            TextButton(
              key: const ValueKey('words-repair-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(wordsStrings(ctx, 'repairDueAction')),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      final next = await _repository.repairDue(_card.id);
      if (!mounted) return;
      if (next == null) {
        _error();
        return;
      }
      _repairPaint(() => _card = next);
    } catch (_) {
      _error();
    } finally {
      if (mounted) _repairPaint(() => _saving = false);
    }
  }
}
