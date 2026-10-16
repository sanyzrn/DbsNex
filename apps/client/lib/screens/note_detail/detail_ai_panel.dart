part of '../note_detail_sheet.dart';

enum _CaptionChoice { append, replace }

/// Explicit AI actions and their output, together above the note's content.
/// Related-note retrieval is intentionally paused; opening this section never
/// invokes a model or performs a semantic-neighbour query.
extension _DetailAiPanel on _NoteDetailSheetState {
  Future<void> _readMedia() async {
    final note = _note;
    if (note == null || _readingMedia) return;
    _rebuild(() {
      _readingMedia = true;
      _showAi = true;
      _activeAiResult = note.isImageMedia ? 'image' : 'transcript';
    });
    String? result;
    try {
      result = await widget.services.readMediaOnDemand(note.id);
      await _reload();
    } catch (_) {
      result = null;
    } finally {
      if (mounted) _rebuild(() => _readingMedia = false);
    }
    if (!mounted || result?.isNotEmpty == true) return;
    final l10n = AppLocalizations.of(context);
    nexShowBanner(
      context,
      message: result == null ? l10n.aiMediaFailed : l10n.aiMediaEmpty,
      kind: result == null ? NexBannerKind.failed : NexBannerKind.done,
    );
  }

  Future<void> _readAttachment(NoteAttachment attachment) async {
    if (_readingAttachments.contains(attachment.id)) return;
    final audio =
        attachment.kind == AttachmentKind.voice ||
        NexFileKinds.of(
              path: attachment.mediaUri,
              mimeType: attachment.mimeType,
            ) ==
            NexFileKind.audio;
    _rebuild(() {
      _readingAttachments.add(attachment.id);
      _showAi = true;
      _activeAiResult =
          'attachment-${attachment.id}-${audio ? 'transcript' : 'image'}';
    });
    var success = false;
    try {
      success = await widget.services.readAttachmentOnDemand(attachment.id);
      await _reload();
    } catch (_) {
      success = false;
    } finally {
      if (mounted) _rebuild(() => _readingAttachments.remove(attachment.id));
    }
    if (!mounted || success) return;
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).aiMediaFailed,
      kind: NexBannerKind.failed,
    );
  }

  Future<void> _addDerivedToCaption(String text) async {
    if (_addingCaption || text.trim().isEmpty) return;
    final l10n = AppLocalizations.of(context);
    _rebuild(() => _addingCaption = true);
    try {
      final current = await widget.services.getById(widget.noteId);
      if (!mounted || current == null) return;
      var choice = _CaptionChoice.append;
      if (current.caption?.trim().isNotEmpty == true) {
        final selected = await nexShowDialog<_CaptionChoice>(
          context: context,
          builder: (dialog) => NexAlertDialog(
            title: Text(l10n.aiAppendCaptionTitle),
            content: NexDialogBody(child: Text(l10n.aiAppendCaptionBody)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(l10n.cancel),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(dialog, _CaptionChoice.append),
                child: Text(l10n.aiAppendCaption),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, _CaptionChoice.replace),
                child: Text(l10n.aiReplaceCaption),
              ),
            ],
          ),
        );
        if (selected == null || !mounted) return;
        choice = selected;
      }
      final replacing = choice == _CaptionChoice.replace;
      final saved = replacing
          ? await widget.services.replaceCaption(
              widget.noteId,
              text,
              expectedCaption: current.caption,
            )
          : await widget.services.appendCaption(widget.noteId, text);
      await _reload();
      if (mounted) {
        nexShowBanner(
          context,
          message: saved
              ? replacing
                    ? l10n.aiCaptionReplaced
                    : l10n.aiCaptionAdded
              : replacing
              ? l10n.aiCaptionChanged
              : l10n.aiCaptionFailed,
          kind: saved ? NexBannerKind.done : NexBannerKind.failed,
        );
      }
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: l10n.aiCaptionFailed,
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) _rebuild(() => _addingCaption = false);
    }
  }

  Future<void> _summarize(String noteId) async {
    if (_summarizing) return;
    _rebuild(() {
      _summarizing = true;
      _showAi = true;
      _activeAiResult = 'summary';
    });
    Summary? summary;
    try {
      summary = await widget.services.summarizeOnDemand(noteId);
      await _reload();
    } catch (_) {
      summary = null;
    } finally {
      if (mounted) _rebuild(() => _summarizing = false);
    }
    if (!mounted || summary != null) return;
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).summarizeFailed,
      kind: NexBannerKind.failed,
      haptics: widget.preferences?.haptics ?? true,
    );
  }

  Future<void> _loadTagSuggestions() async {
    if (_loadingAi) return;
    _rebuild(() => _loadingAi = true);
    try {
      final suggestions = await widget.services.suggestTags(widget.noteId);
      if (mounted) _rebuild(() => _suggestions = suggestions);
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).aiNothingYet,
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) _rebuild(() => _loadingAi = false);
    }
  }

  void _openTranslation() {
    final note = _note;
    if (note == null) return;
    final source = _translationSource(note);
    if (source.isEmpty) return;
    _rebuild(() {
      // Keep the explicitly requested source. Caption edits and tab changes
      // must not silently start a new translation request.
      _translationText = source;
      _translationRequested = true;
      _activeAiResult = 'translation';
    });
  }

  List<_DetailAction> _aiActions(Note note, AppLocalizations l10n) => [
    if (note.isImageMedia && widget.services.imageReadingAvailable)
      _DetailAction(
        icon: Icons.image_search_outlined,
        label: l10n.aiDescribeImage,
        accent: true,
        onPressed: _readingMedia ? null : () => unawaited(_readMedia()),
      ),
    if (note.isAudioMedia && widget.services.audioTranscriptionAvailable)
      _DetailAction(
        icon: Icons.transcribe_outlined,
        label: l10n.aiTranscribeAudio,
        accent: true,
        onPressed: _readingMedia ? null : () => unawaited(_readMedia()),
      ),
    if (widget.preferences case final preferences?
        when preferences.effectiveAiCapabilities.summarization &&
            aiTextAvailableWith(preferences.aiProvider) &&
            (note.aiSourceText?.length ?? 0) > 80)
      _DetailAction(
        glyph: const NexSummariseIcon(),
        label: l10n.summarize,
        accent: true,
        onPressed: _summarizing ? null : () => unawaited(_summarize(note.id)),
      ),
    if (widget.preferences case final preferences?
        when TranslateSheet.availableFor(preferences) &&
            _translationSource(note).isNotEmpty)
      _DetailAction(
        icon: Icons.translate,
        label: l10n.translate,
        accent: true,
        onPressed: _openTranslation,
      ),
    if (widget.preferences case final preferences?
        when AiChatSheet.availableFor(preferences))
      _DetailAction(
        icon: Icons.auto_awesome,
        label: l10n.askAboutNote,
        accent: true,
        onPressed: () => unawaited(
          AiChatSheet.show(
            context,
            preferences: preferences,
            services: widget.services,
            history: preferences.chatHistory,
            focus: note,
          ),
        ),
      ),
  ];

  String _translationSource(Note note) =>
      note.isImageMedia ? note.ocrText?.trim() ?? '' : _translatableText(note);

  List<_AiResult> _derivedAiResults(Note note, AppLocalizations l10n) => [
    if (note.transcriptText?.trim().isNotEmpty == true)
      _AiResult('transcript', l10n.transcript, note.transcriptText!.trim()),
    if (note.ocrText?.trim().isNotEmpty == true)
      _AiResult('image', l10n.aiImageResult, note.ocrText!.trim()),
    if (_summaryIsMeaningful(note))
      _AiResult('summary', l10n.summary, note.summaryText!.trim()),
    for (var i = 0; i < _attachments.length; i++) ...[
      if (_attachments[i].ocrText?.trim().isNotEmpty == true)
        _AiResult(
          'attachment-${_attachments[i].id}-image',
          '${l10n.aiImageResult} · ${nexDigits('${i + 1}', persian: l10n.localeName == 'fa')}',
          _attachments[i].ocrText!.trim(),
        ),
      if (_attachments[i].transcriptText?.trim().isNotEmpty == true)
        _AiResult(
          'attachment-${_attachments[i].id}-transcript',
          '${l10n.transcript} · ${nexDigits('${i + 1}', persian: l10n.localeName == 'fa')}',
          _attachments[i].transcriptText!.trim(),
        ),
    ],
  ];

  Widget _aiPanel(Note note, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final derived = _derivedAiResults(note, l10n);
    final actions = _aiActions(note, l10n);
    final busy =
        _readingMedia ||
        _readingAttachments.isNotEmpty ||
        _summarizing ||
        _loadingAi;
    final canSuggest =
        widget.preferences?.effectiveAiCapabilities.tagSuggestions == true &&
        widget.services.aiIsUsable;
    if (derived.isEmpty && actions.isEmpty && !canSuggest && !busy) {
      return const SizedBox.shrink();
    }
    final translating =
        _translationRequested && _activeAiResult == 'translation';
    final selected =
        derived.where((r) => r.id == _activeAiResult).firstOrNull ??
        derived.lastOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: NexSurface(
        key: const ValueKey('note-ai-workspace'),
        color: scheme.surfaceContainerLow,
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.aiSection,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (busy || (derived.isNotEmpty && !translating))
                  Flexible(
                    child: Text(
                      busy ? l10n.aiProcessing : l10n.aiResultReady,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.sm),
              Wrap(
                spacing: NexSpacing.sm,
                runSpacing: NexSpacing.xs,
                children: [
                  for (final action in actions) _AiActionPill(action: action),
                ],
              ),
            ],
            if (busy) ...[
              const SizedBox(height: NexSpacing.sm),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (derived.isNotEmpty || _translationRequested) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: NexSpacing.sm),
                child: Divider(height: 1),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (derived.length + (_translationRequested ? 1 : 0) >
                            1)
                          Wrap(
                            spacing: NexSpacing.xs,
                            runSpacing: NexSpacing.xs,
                            children: [
                              for (final result in derived)
                                ChoiceChip(
                                  label: Text(result.label),
                                  selected:
                                      !translating && selected?.id == result.id,
                                  onSelected: (_) => _rebuild(
                                    () => _activeAiResult = result.id,
                                  ),
                                ),
                              if (_translationRequested)
                                ChoiceChip(
                                  label: Text(l10n.translate),
                                  selected: translating,
                                  onSelected: (_) => _rebuild(
                                    () => _activeAiResult = 'translation',
                                  ),
                                ),
                            ],
                          )
                        else if (selected != null)
                          Text(
                            selected.label,
                            style: theme.textTheme.labelLarge,
                          ),
                      ],
                    ),
                  ),
                  if (!translating && selected != null)
                    IconButton(
                      tooltip: _showAi
                          ? l10n.aiResultCollapse
                          : l10n.aiResultExpand,
                      onPressed: () => _rebuild(() => _showAi = !_showAi),
                      icon: Icon(
                        _showAi ? Icons.unfold_less : Icons.unfold_more,
                        size: 20,
                      ),
                    ),
                ],
              ),
              if (!translating && selected != null) ...[
                const SizedBox(height: NexSpacing.sm),
                if (_showAi)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      key: ValueKey('ai-result-${selected.id}'),
                      primary: false,
                      child: NexTextSurface(selected.text, selectable: true),
                    ),
                  )
                else
                  NexTextSurface(selected.text, maxLines: 3),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(_copyDerivedText(selected.text)),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(l10n.copy),
                    ),
                    TextButton.icon(
                      key: ValueKey('add-derived-caption-${selected.id}'),
                      onPressed: _addingCaption
                          ? null
                          : () =>
                                unawaited(_addDerivedToCaption(selected.text)),
                      icon: const Icon(Icons.playlist_add_outlined, size: 18),
                      label: Text(l10n.aiAddToCaption),
                    ),
                  ],
                ),
              ],
              if (widget.preferences case final preferences?
                  when _translationRequested)
                Visibility(
                  visible: translating,
                  maintainState: true,
                  child: TranslateSheet(
                    key: ValueKey(
                      'note-translation-${note.id}-${_translationText.hashCode}',
                    ),
                    text: _translationText,
                    preferences: preferences,
                    services: widget.services,
                    embedded: true,
                    addingCaption: _addingCaption,
                    onAddToCaption: (text) =>
                        unawaited(_addDerivedToCaption(text)),
                  ),
                ),
            ] else if (!busy) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(
                l10n.aiNoResult,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canSuggest)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _loadingAi
                      ? null
                      : () => unawaited(_loadTagSuggestions()),
                  icon: const Icon(Icons.label_outline, size: 18),
                  label: Text(l10n.aiTagsAction),
                ),
              ),
            if (_suggestions.isNotEmpty)
              Wrap(
                spacing: NexSpacing.xs,
                runSpacing: NexSpacing.xs,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      label: Text(suggestion.name),
                      onPressed: () async {
                        await widget.services.addTag(
                          noteId: note.id,
                          name: suggestion.name,
                        );
                        if (!mounted) return;
                        _rebuild(
                          () => _suggestions = _suggestions
                              .where((s) => s.name != suggestion.name)
                              .toList(),
                        );
                        await _reload();
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _summaryIsMeaningful(Note note) {
    final summary = note.summaryText?.trim();
    if (summary == null || summary.isEmpty) return false;
    final source = (note.aiSourceText ?? '').trim();
    if (source.isEmpty) return true;
    return summary != source && summary.length < source.length;
  }
}
