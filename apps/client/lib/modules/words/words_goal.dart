import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_store.dart';
import 'words_strings.dart';

/// The small daily goal, chosen in the app's own dialog — five answers, ten,
/// twenty, thirty, or none at all. It is an invitation, not a debt: a day
/// without answers costs nothing, and nothing counts a streak.
class WordsGoalRow extends StatefulWidget {
  const WordsGoalRow({
    super.key,
    required this.settings,
    required this.repository,
  });

  final WordsSettings settings;
  final WordsRepository repository;

  @override
  State<WordsGoalRow> createState() => _WordsGoalRowState();
}

class _WordsGoalRowState extends State<WordsGoalRow> {
  bool _busy = false;

  static const _choices = [5, 10, 20, 30, 0];

  String _label(BuildContext context, int value) => wordsStrings(
    context,
    value == 0 ? 'goalNone' : 'goalPerDayCount',
    {'count': value},
  );

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final current = widget.settings.goalPerDay;
      final picked = await nexShowDialog<int>(
        context: context,
        builder: (ctx) => NexAlertDialog(
          title: Text(wordsStrings(ctx, 'dailyGoal')),
          contentPadding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          content: NexDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in _choices)
                  ListTile(
                    key: ValueKey('words-goal-$value'),
                    selected: value == current,
                    title: Text(_label(ctx, value)),
                    trailing: value == current
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(ctx, value),
                  ),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      final saved = await widget.repository.updateSettings(goalPerDay: picked);
      if (!saved && mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: wordsStrings(context, 'saveFailed'),
        );
      }
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: wordsStrings(context, 'saveFailed'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: NexSpacing.sm,
      children: [
        Text(
          wordsStrings(context, 'dailyGoal'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          // The hero's goal pill is `words-goal`; this row is its picker.
          key: const ValueKey('words-goal-pick'),
          onPressed: _busy ? null : () => unawaited(_pick()),
          child: Text(_label(context, widget.settings.goalPerDay)),
        ),
      ],
    );
  }
}
