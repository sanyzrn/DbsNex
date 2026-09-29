import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/feedback_service.dart';
import 'nex_dialog.dart';
import 'nex_banner.dart';

import 'feature_label.dart';

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
  final _contact = TextEditingController();
  FeedbackKind _kind = FeedbackKind.idea;
  bool _sending = false;
  FeedbackOutcome? _lastFailure;

  @override
  void dispose() {
    _controller.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _lastFailure = null;
    });

    final outcome = await widget.service.send(
      text,
      kind: _kind,
      contact: _contact.text,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    switch (outcome) {
      case FeedbackOutcome.sent:
        Navigator.pop(context);
        nexShowBanner(context, message: l10n.feedbackSent);
      case FeedbackOutcome.offline:
        await widget.service.preferences.setPendingFeedback(
          FeedbackService.encodePending(
            text,
            kind: _kind,
            contact: _contact.text,
          ),
        );
        if (!mounted) return;
        Navigator.pop(context);
        nexShowBanner(context, message: l10n.feedbackQueuedOffline);
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
          const SizedBox(height: NexSpacing.xs),
          Text(
            nexLabel(
              context,
              'Goes straight to the people who make Nex. Nothing from your notes is attached.',
              'مستقیم به سازندگان Nex می‌رسد. چیزی از یادداشت‌هایتان پیوست نمی‌شود.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          SegmentedButton<FeedbackKind>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: FeedbackKind.bug,
                icon: const Icon(Icons.bug_report_outlined),
                label: Text(nexLabel(context, 'Problem', 'مشکل')),
              ),
              ButtonSegment(
                value: FeedbackKind.idea,
                icon: const Icon(Icons.lightbulb_outline),
                label: Text(nexLabel(context, 'Idea', 'ایده')),
              ),
              ButtonSegment(
                value: FeedbackKind.other,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(nexLabel(context, 'Other', 'سایر')),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: _sending
                ? null
                : (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: NexSpacing.md),
          NexAutoDirection(
            controller: _controller,
            builder: (context, direction) => TextField(
              controller: _controller,
              selectionWidthStyle: BoxWidthStyle.tight,
              contextMenuBuilder: nexReadingMenu,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textDirection: direction,
              textAlign: TextAlign.start,
              decoration: InputDecoration(
                hintText: l10n.feedbackHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          TextField(
            controller: _contact,
            maxLength: 80,
            contextMenuBuilder: nexReadingMenu,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              counterText: '',
              prefixIcon: const Icon(Icons.alternate_email),
              labelText: nexLabel(
                context,
                'How to reach you (optional)',
                'راه ارتباط با شما (اختیاری)',
              ),
              hintText: nexLabel(
                context,
                'Telegram ID or email, if you want a reply',
                'آیدی تلگرام یا ایمیل، اگر پاسخ می‌خواهید',
              ),
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
            // The old fallback copied a link to this repository's issue
            // tracker, which is private: nobody outside could open it. The
            // words are what matter, so they are what gets kept.
            InkWell(
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: _controller.text.trim()),
                );
                if (!context.mounted) return;
                nexShowBanner(context, message: l10n.copied);
              },
              child: Text(
                nexLabel(
                  context,
                  'Copy your message to send it another way (DbsStudio.ir)',
                  'پیامتان را کپی کنید تا از راه دیگری بفرستید (DbsStudio.ir)',
                ),
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
