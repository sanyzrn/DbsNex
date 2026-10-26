import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/nex_preferences.dart';
import '../platform/crash_reporter.dart';
import '../platform/nex_services.dart';
import 'nex_banner.dart';

/// A note in the other language, inside its AI workspace (rebuilt in 2.3.3).
///
/// The direction is worked out, not asked: a Persian note goes into English
/// and an English one into Persian, shown as one line — "Persian → English".
/// It used to offer both languages as equal choices, and the one that matched
/// the note asked the model to translate a note into its own language, which
/// failed. Only a note written in both, where either way is a real request,
/// gets a swap.
///
/// Translation never changes the source. What comes back can be copied,
/// kept as a new note, or (for media) added to the caption, and it is kept
/// for the session: hiding it, switching tabs or opening the note again
/// shows it without asking a second time.
class TranslateSheet extends StatefulWidget {
  const TranslateSheet({
    super.key,
    required this.text,
    required this.preferences,
    required this.services,
    this.onAddToCaption,
    this.addingCaption = false,
    this.adapter,
    this.noteId,
  });

  /// The note [text] came from, named in the log of what left the phone.
  final String? noteId;

  /// The words to translate, already resolved by the caller — a photo's
  /// extracted text is as translatable as anything typed.
  final String text;

  final NexPreferences preferences;
  final NexServices services;
  final ValueChanged<String>? onAddToCaption;
  final bool addingCaption;

  /// An injected adapter is owned and closed by this widget, like its default.
  final CloudAIAdapter? adapter;

  /// Whether there is a provider configured to do this at all.
  static bool availableFor(NexPreferences preferences) =>
      preferences.aiEnabled && aiTextAvailableWith(preferences.aiProvider);

  /// Whether [text] already has a translation this session, so its tab can
  /// come back with the note.
  static bool hasTranslation(String text) =>
      _memory.containsKey(_key(text, nexTranslationTarget(text)));

  @visibleForTesting
  static void forgetAll() => _memory.clear();

  static final _memory = <String, String>{};
  static String _key(String text, AiOutputLanguage target) =>
      '${target.name}:${text.length}:${text.hashCode}';

  static void _remember(String text, AiOutputLanguage target, String result) {
    _memory.remove(_key(text, target));
    _memory[_key(text, target)] = result;
    // A handful is plenty: it is the notes looked at in one sitting.
    while (_memory.length > 40) {
      _memory.remove(_memory.keys.first);
    }
  }

  @override
  State<TranslateSheet> createState() => _TranslateSheetState();
}

/// Which way [text] is translated by default: into whichever of the two
/// languages it is mostly *not* written in.
AiOutputLanguage nexTranslationTarget(String text) =>
    nexPersianShare(text) >= 0.5
    ? AiOutputLanguage.english
    : AiOutputLanguage.persian;

/// How much of [text]'s lettering is Persian (Arabic script), from 0 to 1.
double nexPersianShare(String text) {
  var persian = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0xFB50 && rune <= 0xFEFF)) {
      persian++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    }
  }
  final letters = persian + latin;
  return letters == 0 ? 0 : persian / letters;
}

class _TranslateSheetState extends State<TranslateSheet> {
  late AiOutputLanguage _target = nexTranslationTarget(widget.text);
  late final CloudAIAdapter _adapter =
      widget.adapter ?? CloudAIAdapter(config: widget.preferences.aiProvider);

  String? _result;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;

  /// Written in both languages in earnest, so either direction is a real
  /// request and the swap is offered.
  late final bool _mixed = () {
    final share = nexPersianShare(widget.text);
    return share > 0.25 && share < 0.75;
  }();

  @override
  void initState() {
    super.initState();
    _result = TranslateSheet._memory[TranslateSheet._key(widget.text, _target)];
    if (_result == null) unawaited(_translate());
  }

  @override
  void dispose() {
    _adapter.close();
    super.dispose();
  }

  Future<void> _translate() async {
    final request = ++_request;
    final target = _target;
    setState(() {
      _loading = true;
      _failed = false;
    });
    String? text;
    try {
      text = await NexDisclosureLog.about(
        notes: [?widget.noteId],
        () => _adapter.translate(widget.text, target: target),
      );
    } catch (error) {
      unawaited(NexCrashLog.handled('translation', error));
      text = null;
    }
    if (!mounted || request != _request) return;
    final ok = text != null && text.isNotEmpty;
    if (ok) TranslateSheet._remember(widget.text, target, text);
    setState(() {
      _loading = false;
      _failed = !ok;
      // A failed retry keeps the translation already on screen: it is still
      // readable, and a dropped connection should not take it away.
      if (ok) _result = text;
    });
  }

  void _swap() {
    setState(() {
      _target = _target == AiOutputLanguage.english
          ? AiOutputLanguage.persian
          : AiOutputLanguage.english;
      _result =
          TranslateSheet._memory[TranslateSheet._key(widget.text, _target)];
      _failed = false;
    });
    if (_result == null) unawaited(_translate());
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    nexBump();
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).copied,
      haptics: widget.preferences.haptics,
    );
  }

  Future<void> _keep(String text) async {
    final host = NexBannerHost.of(context);
    final message = AppLocalizations.of(context).translateSaved;
    await widget.services.captureText(text);
    widget.services.refreshTimeline();
    if (!mounted) return;
    nexBump();
    host?.show(message: message, haptics: widget.preferences.haptics);
  }

  String _name(AiOutputLanguage language, AppLocalizations l10n) =>
      language == AiOutputLanguage.english
      ? l10n.aiOutputLanguageEnglish
      : l10n.aiOutputLanguagePersian;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    final source = _target == AiOutputLanguage.english
        ? AiOutputLanguage.persian
        : AiOutputLanguage.english;
    return Column(
      key: const ValueKey('translation'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The way it goes, as one line rather than a choice.
        Container(
          key: const ValueKey('translation-direction'),
          padding: const EdgeInsetsDirectional.only(
            start: NexSpacing.md,
            end: NexSpacing.xs,
          ),
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(NexRadius.pill),
          ),
          child: Row(
            children: [
              // The direction takes the line, so the buttons sit at its far
              // end rather than wherever a shared flex left them (2.3.4).
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.translate, size: 18, color: scheme.primary),
                    const SizedBox(width: NexSpacing.sm),
                    Flexible(
                      child: Text(
                        _name(source, l10n),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexSpacing.xs,
                      ),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _name(_target, l10n),
                        key: const ValueKey('translation-target'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_mixed)
                IconButton(
                  key: const ValueKey('translation-swap'),
                  tooltip: l10n.translateSwap,
                  onPressed: _loading ? null : _swap,
                  icon: const Icon(Icons.swap_horiz, size: 20),
                ),
              if (result != null)
                IconButton(
                  key: const ValueKey('translation-again'),
                  tooltip: l10n.translateAgain,
                  onPressed: _loading ? null : () => unawaited(_translate()),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        NexAnimatedSize(
          child: _loading && result == null
              ? Semantics(
                  label: l10n.translateWorking,
                  liveRegion: true,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NexSkeleton(height: 14),
                      SizedBox(height: NexSpacing.sm),
                      NexSkeleton(height: 14),
                      SizedBox(height: NexSpacing.sm),
                      FractionallySizedBox(
                        widthFactor: 0.6,
                        child: NexSkeleton(height: 14),
                      ),
                    ],
                  ),
                )
              : result == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.sm,
                  ),
                  child: AnimatedOpacity(
                    opacity: _loading ? 0.45 : 1,
                    duration: NexMotion.standard,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        primary: false,
                        // The translation's direction comes from the
                        // translation, not from the note it came from.
                        child: NexTextSurface(
                          result,
                          key: const ValueKey('translation-result'),
                          selectable: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (_failed && !_loading) ...[
          const SizedBox(height: NexSpacing.sm),
          Container(
            key: const ValueKey('translation-failed'),
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.md,
              end: NexSpacing.xs,
              top: NexSpacing.xs,
              bottom: NexSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    _adapter.lastReplyTruncated
                        ? l10n.aiIncompleteReply
                        : l10n.translateFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                // Flexible: at the largest text sizes the button shares the
                // line rather than pushing past the edge.
                Flexible(
                  child: TextButton(
                    onPressed: () => unawaited(_translate()),
                    child: Text(
                      l10n.retry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.xs,
            runSpacing: NexSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: _loading ? null : () => unawaited(_copy(result)),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.copy),
              ),
              if (widget.onAddToCaption case final add?)
                TextButton.icon(
                  onPressed: _loading || widget.addingCaption
                      ? null
                      : () => add(result),
                  icon: const Icon(Icons.playlist_add_outlined, size: 18),
                  label: Text(l10n.aiAddToCaption),
                ),
              TextButton.icon(
                onPressed: _loading ? null : () => unawaited(_keep(result)),
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: Text(l10n.translateSaveAsNote),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
