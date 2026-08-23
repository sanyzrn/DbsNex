import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';

/// A note in the other language, read side by side with itself.
///
/// Deliberately not an edit. Translation here is a reading aid — the note is
/// in Persian and is being read in English, or the other way round — and
/// replacing the note's own words with a machine's version of them is the one
/// outcome nobody can undo. What it offers instead is the two things someone
/// actually wants with a translation in hand: copy it, or keep it as a note of
/// its own beside the original.
class TranslateSheet extends StatefulWidget {
  const TranslateSheet({
    super.key,
    required this.text,
    required this.preferences,
    required this.services,
  });

  /// The note's own words. Already resolved by the caller — a voice note's
  /// transcript and a photo's extracted text are as translatable as anything
  /// typed, and the sheet should not have to know which it was handed.
  final String text;

  final NexPreferences preferences;
  final NexServices services;

  /// Whether there is a provider configured to do this at all.
  static bool availableFor(NexPreferences preferences) =>
      preferences.aiEnabled && aiTextAvailableWith(preferences.aiProvider);

  static Future<void> show(
    BuildContext context, {
    required String text,
    required NexPreferences preferences,
    required NexServices services,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TranslateSheet(
      text: text,
      preferences: preferences,
      services: services,
    ),
  );

  @override
  State<TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<TranslateSheet> {
  late AiOutputLanguage _target = _opposite;
  late final CloudAIAdapter _adapter = CloudAIAdapter(
    config: widget.preferences.aiProvider,
  );

  String? _result;
  bool _loading = false;
  bool _failed = false;

  /// The language the note is *not* in.
  ///
  /// The whole reason to open this sheet is that the note is hard to read, so
  /// the useful default is the other language — never the app's own output
  /// language, which would offer to translate a Persian note into Persian for
  /// anyone who set that once and forgot.
  AiOutputLanguage get _opposite =>
      nexDirectionOf(widget.text) == TextDirection.rtl
      ? AiOutputLanguage.english
      : AiOutputLanguage.persian;

  @override
  void initState() {
    super.initState();
    unawaited(_translate());
  }

  @override
  void dispose() {
    _adapter.close();
    super.dispose();
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    String? text;
    try {
      text = await _adapter.translate(widget.text, target: _target);
    } catch (_) {
      text = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = text == null || text.isEmpty;
      // A failed retry keeps the previous translation on screen rather than
      // blanking it: the words that are already there are still readable, and
      // a dropped connection should not take them away.
      if (text != null && text.isNotEmpty) _result = text;
    });
  }

  void _retarget(AiOutputLanguage value) {
    if (value == _target) return;
    setState(() => _target = value);
    unawaited(_translate());
  }

  Future<void> _copy() async {
    final text = _result;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    nexBump();
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).copied,
      haptics: widget.preferences.haptics,
    );
  }

  Future<void> _keep() async {
    final text = _result;
    if (text == null) return;
    // Both captured before the sheet goes: the confirmation is shown *after*
    // this widget is gone, and reaching back through its context then is the
    // "deactivated widget's ancestor" crash rather than a missing toast.
    final host = NexBannerHost.of(context);
    final message = AppLocalizations.of(context).translateSaved;
    await widget.services.captureText(text);
    widget.services.refreshTimeline();
    if (!mounted) return;
    nexBump();
    Navigator.pop(context);
    host?.show(message: message, haptics: widget.preferences.haptics);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = _result;
    return NexSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.translate, style: theme.textTheme.titleMedium),
          const SizedBox(height: NexSpacing.md),
          Text(l10n.translateTo, style: theme.textTheme.bodySmall),
          const SizedBox(height: NexSpacing.sm),
          // Two, not three: `auto` means "the language of the notes", which
          // as a translation target is a request to translate a note into its
          // own language.
          Row(
            children: [
              for (final language in const [
                AiOutputLanguage.english,
                AiOutputLanguage.persian,
              ]) ...[
                if (language != AiOutputLanguage.english)
                  const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: ChoiceChip(
                    selected: _target == language,
                    onSelected: _loading ? null : (_) => _retarget(language),
                    label: Text(
                      language == AiOutputLanguage.english
                          ? l10n.aiOutputLanguageEnglish
                          : l10n.aiOutputLanguagePersian,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: NexSpacing.sm),
                  Text(l10n.translateWorking, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (result != null)
            Flexible(
              child: SingleChildScrollView(
                child: Opacity(
                  opacity: _loading ? 0.45 : 1,
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      result,
                      // The translation's direction comes from the
                      // translation, not from the note it came from — that is
                      // the whole point of having changed language.
                      textDirection: nexDirectionOf(result),
                      textAlign: TextAlign.start,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
            ),
          if (_failed && !_loading) ...[
            Text(
              l10n.translateFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => unawaited(_translate()),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.retry),
              ),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: NexSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => unawaited(_copy()),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(l10n.copy),
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => unawaited(_keep()),
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: Text(l10n.translateSaveAsNote),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
