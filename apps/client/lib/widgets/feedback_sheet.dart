import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/feedback_service.dart';
import 'nex_dialog.dart';
import 'nex_toast.dart';

const _issuesUrl = 'https://github.com/sanyzrn/DbsNex/issues/new';

/// A compose-and-send sheet, replacing what used to be a single row that only
/// copied a GitHub issues link — the actual complaint this answers is that
/// nothing about the old row felt like "feedback" at all.
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.service});

  final FeedbackService service;

  static Future<void> show(
    BuildContext context, {
    required FeedbackService service,
  }) => nexShowSheet<void>(
    context: context,
    builder: (_) => FeedbackSheet(service: service),
  );

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  FeedbackOutcome? _lastFailure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _lastFailure = null;
    });

    final outcome = await widget.service.send(text);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    switch (outcome) {
      case FeedbackOutcome.sent:
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(nexToast(content: Text(l10n.feedbackSent)));
      case FeedbackOutcome.offline:
        await widget.service.preferences.setPendingFeedback(text);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(nexToast(content: Text(l10n.feedbackQueuedOffline)));
      case FeedbackOutcome.failed:
      case FeedbackOutcome.unavailable:
        // Kept open, with the typed text still in the field: a failure here
        // is not something to lose someone's words over.
        setState(() {
          _sending = false;
          _lastFailure = outcome;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return NexSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.sendFeedback, style: theme.textTheme.titleLarge),
          const SizedBox(height: NexSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: l10n.feedbackHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_lastFailure != null) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              _lastFailure == FeedbackOutcome.unavailable
                  ? l10n.feedbackUnavailable
                  : l10n.feedbackFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: NexSpacing.xs),
            InkWell(
              onTap: () =>
                  Clipboard.setData(const ClipboardData(text: _issuesUrl)),
              child: Text(
                l10n.feedbackOpenIssueInstead,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.lg),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.feedbackSend),
          ),
        ],
      ),
    );
  }
}
