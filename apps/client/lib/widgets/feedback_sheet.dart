import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/crash_reporter.dart';
import '../platform/feedback_service.dart';
import '../platform/metrics.dart';
import 'nex_dialog.dart';
import 'nex_banner.dart';

import 'feature_label.dart';
import 'nex_text_field.dart';

/// A compose-and-send sheet, replacing what used to be a single row that only
/// copied a GitHub issues link — the actual complaint this answers is that
/// nothing about the old row felt like "feedback" at all.
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({
    super.key,
    required this.service,
    this.metrics,
    this.loadDiagnostics,
    this.idea = false,
  });

  final FeedbackService service;

  /// An idea for a module, from the foot of the Modules page: the same
  /// sending, in a sheet that asks for nothing else — no kind to pick, no
  /// measurements or diagnostics, which belong to reporting a problem.
  final bool idea;

  /// The measurements that may be attached; [NexMetrics.shared] unless a test
  /// passes its own.
  final NexMetrics? metrics;

  /// Reads the diagnostics report that may be attached; the app's own
  /// crash log unless a test passes its own.
  final Future<String?> Function()? loadDiagnostics;

  static Future<void> show(
    BuildContext context, {
    required FeedbackService service,
    bool idea = false,
  }) => nexShowSheet<void>(
    context: context,
    builder: (_) => FeedbackSheet(service: service, idea: idea),
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

  /// Whether the measurements go with this message (W3.4). Never ticked on
  /// its own: attaching them is something the person does, every time.
  bool _attachMetrics = false;

  /// Whether the diagnostics report goes with this message. Never ticked on
  /// its own, like the measurements: sending it is the person's choice,
  /// every time, after seeing exactly what it says.
  bool _attachDiagnostics = false;

  /// The redacted report, or null when there is nothing recorded.
  String? _diagnostics;

  @override
  void initState() {
    super.initState();
    _readDiagnostics();
  }

  Future<void> _readDiagnostics() async {
    String? report;
    try {
      final load = widget.loadDiagnostics;
      report = load != null
          ? await load()
          : (await NexCrashLog.open()).shareable();
    } catch (_) {
      report = null;
    }
    if (mounted && report != null && report.trim().isNotEmpty) {
      setState(() => _diagnostics = report);
    }
  }

  NexMetrics get _metrics => widget.metrics ?? NexMetrics.shared;

  bool get _canAttach => _metrics.enabled && !_metrics.isEmpty;

  String get _report => _metrics.report(platform: Platform.operatingSystem);

  @override
  void dispose() {
    _controller.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final typed = _controller.text.trim();
    if (typed.isEmpty || _sending) return;
    // Appended as text, exactly as shown under the box, so what is sent is
    // what was read; the server holds a message to 4,000 characters.
    final text = widget.idea
        ? 'Module idea:\n$typed'
        : _attachMetrics && _canAttach
        ? '$typed\n\n$_report'
        : typed;
    setState(() {
      _sending = true;
      _lastFailure = null;
    });

    final diagnostics = _attachDiagnostics && !widget.idea
        ? _diagnostics
        : null;
    final outcome = await widget.service.send(
      text,
      kind: _kind,
      contact: _contact.text,
      diagnostics: diagnostics,
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
            diagnostics: diagnostics,
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
    if (widget.idea) return _ideaBody(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return NexSheetBody(
      // Scrollable: the sheet's body is `Flexible`, and a message box, a
      // reply field and the attached measurements do not fit a small phone
      // with the keyboard up.
      child: SingleChildScrollView(
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
            NexTextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n.feedbackHint,
                border: const OutlineInputBorder(),
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
            if (_canAttach) ...[
              const SizedBox(height: NexSpacing.xs),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _attachMetrics,
                onChanged: _sending
                    ? null
                    : (value) =>
                          setState(() => _attachMetrics = value ?? false),
                title: Text(l10n.feedbackAttachMetrics),
                subtitle: Text(l10n.feedbackAttachMetricsHint),
              ),
              if (_attachMetrics)
                Container(
                  padding: const EdgeInsets.all(NexSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(NexRadius.sm),
                  ),
                  child: Text(
                    _report,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            if (_diagnostics != null) ...[
              CheckboxListTile(
                key: const ValueKey('feedback-attach-diagnostics'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _attachDiagnostics,
                onChanged: _sending
                    ? null
                    : (value) =>
                          setState(() => _attachDiagnostics = value ?? false),
                title: Text(
                  nexLabel(
                    context,
                    'Attach the diagnostics report',
                    'پیوست گزارش عیب‌یابی',
                  ),
                ),
                subtitle: Text(
                  nexLabel(
                    context,
                    'Recent errors and app events, with links, keys and passwords removed. Nothing from your notes. Shown below before sending.',
                    'خطاها و رویدادهای اخیر برنامه، بدون لینک، کلید و رمز. چیزی از یادداشت‌هایتان در آن نیست. پیش از ارسال در زیر نشان داده می‌شود.',
                  ),
                ),
              ),
              if (_attachDiagnostics)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(NexSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(NexRadius.sm),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _diagnostics!,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
            ],
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
      ),
    );
  }

  /// The idea sheet: a lit bulb over the question, one box for the idea and
  /// one for a way back, and a button that says what it sends.
  Widget _ideaBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NexSheetBody(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _IdeaGlow(color: scheme.primary)),
            const SizedBox(height: NexSpacing.md),
            Text(
              l10n.moduleIdeaTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.moduleIdeaLead,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            NexTextField(
              key: const ValueKey('module-idea-text'),
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n.moduleIdeaHint,
                filled: true,
                fillColor: scheme.primary.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NexRadius.lg),
                  borderSide: BorderSide.none,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NexRadius.lg),
                ),
              ),
            ),
            if (_lastFailure != null) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(
                _lastFailure == FeedbackOutcome.unavailable
                    ? l10n.feedbackUnavailable
                    : l10n.feedbackFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: NexSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('module-idea-send'),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(l10n.moduleIdeaSend),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bulb in a soft halo that breathes once as the sheet opens: an idea
/// being lit, not a form being filled.
class _IdeaGlow extends StatelessWidget {
  const _IdeaGlow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: NexMotion.of(context, NexMotion.morph + NexMotion.enter),
    curve: NexMotion.curve,
    builder: (context, t, child) => Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.10 + 0.18 * t),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
          ),
          child: Icon(
            t > 0.5 ? Icons.lightbulb : Icons.lightbulb_outline,
            color: color,
          ),
        ),
      ),
    ),
  );
}
