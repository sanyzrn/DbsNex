import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import '../platform/nex_preferences.dart';
import 'ai_failure_message.dart';
import 'nex_dialog.dart';
import '../platform/nex_services.dart';
import 'nex_banner.dart';

part 'translation_workspace.dart';
part 'translation_language_picker.dart';

/// Translation in the existing Nex AI result surface. Process-only jobs keep
/// completed chunks and live requests when the note or its result is hidden.
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
  static bool hasTranslation(
    String text, {
    String? noteId,
    NexPreferences? preferences,
  }) => _memory.entries.any(
    (entry) =>
        entry.value.source == text &&
        !entry.value.invalidated &&
        (noteId == null || entry.key.$2 == noteId) &&
        (preferences == null || identical(entry.key.$1, preferences)),
  );

  static final _memory =
      <(NexPreferences, String?, String), _TranslationWorkspace>{};

  static void invalidate(String noteId, String currentSource) {
    final stale = _memory.keys
        .where((key) => key.$2 == noteId && key.$3 != currentSource)
        .toList();
    for (final key in stale) {
      _memory.remove(key)?.invalidated = true;
    }
  }

  @visibleForTesting
  static void forgetAll() {
    for (final job in _memory.values) {
      job.invalidated = true;
    }
    _memory.clear();
  }

  @override
  State<TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<TranslateSheet> {
  late _TranslationWorkspace _job;
  bool _attached = false;
  NexTranslationLanguage get _target => _job.target;
  String? get _result => _job.result.isEmpty ? null : _job.result;
  bool get _loading => _job.loading;
  bool get _failed => _job.failure != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_attached) _attach();
  }

  void _attach() {
    final locale = AppLocalizations.of(context).localeName;
    final noteId = widget.noteId;
    if (noteId != null) TranslateSheet.invalidate(noteId, widget.text);
    final key = (widget.preferences, noteId, widget.text);
    _job = TranslateSheet._memory.putIfAbsent(
      key,
      () => _TranslationWorkspace(
        widget.text,
        noteId,
        NexTranslationLanguage.fromCode(widget.preferences.translationTarget) ??
            NexTranslationLanguage.fromCode(locale) ??
            NexTranslationLanguage.values[1],
        explicitTarget: false,
      ),
    );
    while (TranslateSheet._memory.length > 12) {
      final idle = TranslateSheet._memory.entries.where(
        (entry) => !entry.value.loading && !identical(entry.value, _job),
      );
      if (idle.isEmpty) break;
      TranslateSheet._memory.remove(idle.first.key);
    }
    _job.addListener(_changed);
    _attached = true;
    if (!_job.started && !_job.needsConsent && !_job.tooLarge) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_translate());
      });
    }
  }

  @override
  void didUpdateWidget(covariant TranslateSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.noteId != widget.noteId ||
        oldWidget.preferences != widget.preferences) {
      _job.removeListener(_changed);
      _attach();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _job.removeListener(_changed);
    super.dispose();
  }

  Future<void> _translate() =>
      _job.run(widget.preferences, adapter: widget.adapter);

  Future<void> _chooseLanguage() async {
    final selected = await nexShowSheet<NexTranslationLanguage>(
      context: context,
      builder: (_) => _TranslationLanguagePicker(selected: _target),
    );
    if (!mounted || selected == null || _loading) return;
    _job.choose(selected);
    await widget.preferences.setTranslationTarget(selected.code);
    if (mounted && !_job.needsConsent && !_job.complete) await _translate();
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

  String _name(String code, AppLocalizations l10n) {
    final language = NexTranslationLanguage.fromCode(code);
    return language == null
        ? code
        : l10n.localeName == 'fa'
        ? language.persian
        : language.english;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    final languages = _job.languages;
    final source = languages == null || languages.isEmpty
        ? l10n.translationAutoDetect
        : languages.map((code) => _name(code, l10n)).join(' + ');
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
                        source,
                        key: const ValueKey('translation-source'),
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
                        _name(_target.code, l10n),
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
              IconButton(
                key: const ValueKey('translation-choose-language'),
                tooltip: l10n.translationChooseLanguage,
                onPressed: _loading ? null : () => unawaited(_chooseLanguage()),
                icon: const Icon(Icons.expand_more, size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        if (_job.suggestedTarget) ...[
          Text(
            l10n.translationSuggestedLanguage,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
        if (_job.tooLarge)
          Text(
            l10n.translationTooLarge,
            key: const ValueKey('translation-too-large'),
            style: theme.textTheme.bodyMedium,
          )
        else if (_job.needsConsent) ...[
          Text(l10n.translationLongWarning, style: theme.textTheme.bodyMedium),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              FilledButton.tonal(
                key: const ValueKey('translation-continue'),
                onPressed: () {
                  _job.consent = true;
                  unawaited(_translate());
                },
                child: Text(l10n.translationContinue),
              ),
              TextButton(
                onPressed: () => setState(() => _job.cancelled = true),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ] else if (_job.cancelled && !_job.started)
          TextButton(
            onPressed: () => setState(() => _job.cancelled = false),
            child: Text(l10n.translationContinue),
          ),
        if (_loading || _job.completedChunks > 0 && !_job.complete) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              !_job.detectionAttempted && _loading && _job.completedChunks == 0
                  ? l10n.translationDetecting
                  : l10n.translationProgress(
                      nexDigits(
                        '${_job.completedChunks}',
                        persian: l10n.localeName == 'fa',
                      ),
                      nexDigits(
                        '${_job.chunks.length}',
                        persian: l10n.localeName == 'fa',
                      ),
                    ),
              key: const ValueKey('translation-progress'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          LinearProgressIndicator(
            value: _job.chunks.isEmpty
                ? 0
                : _job.completedChunks / _job.chunks.length,
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        NexAnimatedSize(
          child: result == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.sm,
                  ),
                  child: AnimatedOpacity(
                    opacity: 1,
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
                    nexAiFailureMessage(_job.failure, l10n),
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
        if (result != null && _job.complete) ...[
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

String _languageName(String code, AppLocalizations l10n) {
  final language = NexTranslationLanguage.fromCode(code);
  return language == null
      ? code
      : l10n.localeName == 'fa'
      ? language.persian
      : language.english;
}
