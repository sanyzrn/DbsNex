import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'words_models.dart';
import 'words_store.dart';
import 'words_strings.dart';

class WordsDailyCapRow extends StatefulWidget {
  const WordsDailyCapRow({
    super.key,
    required this.settings,
    required this.repository,
    this.session = false,
  });
  final WordsSettings settings;
  final WordsRepository repository;
  final bool session;
  @override
  State<WordsDailyCapRow> createState() => _WordsDailyCapRowState();
}

class _WordsDailyCapRowState extends State<WordsDailyCapRow> {
  bool _busy = false;
  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await nexShowDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(
            wordsStrings(ctx, widget.session ? 'sessionCap' : 'dailyCap'),
          ),
          children: [
            for (final value
                in widget.session
                    ? const [10, 20, 40, 0]
                    : const [5, 10, 20, 0])
              SimpleDialogOption(
                key: ValueKey(
                  widget.session
                      ? 'words-session-cap-$value'
                      : 'words-cap-$value',
                ),
                onPressed: () => Navigator.pop(ctx, value),
                child: Text(
                  wordsStrings(
                    ctx,
                    value == 0
                        ? widget.session
                              ? 'sessionCapOff'
                              : 'dailyCapOff'
                        : widget.session
                        ? 'sessionCount'
                        : 'dailyPerDay',
                    {'count': value},
                  ),
                ),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      final saved = await widget.repository.updateSettings(
        newPerDay: widget.session ? null : picked,
        sessionLimit: widget.session ? picked : null,
      );
      if (!saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.session
        ? widget.settings.sessionLimit
        : widget.settings.newPerDay;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: NexSpacing.sm,
      children: [
        Text(
          wordsStrings(context, widget.session ? 'sessionCap' : 'dailyCap'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          key: ValueKey(
            widget.session ? 'words-session-cap' : 'words-daily-cap',
          ),
          onPressed: _busy ? null : () => unawaited(_pick()),
          child: Text(
            wordsStrings(
              context,
              value == 0
                  ? widget.session
                        ? 'sessionCapOff'
                        : 'dailyCapOff'
                  : widget.session
                  ? 'sessionCount'
                  : 'dailyPerDay',
              {'count': value},
            ),
          ),
        ),
      ],
    );
  }
}
