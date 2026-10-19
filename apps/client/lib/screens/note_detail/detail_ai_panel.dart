part of '../note_detail_sheet.dart';

enum _CaptionChoice { append, replace }

/// Explicit AI actions and their output, together below the note's content.
/// Related-note retrieval is intentionally paused; opening this section never
/// invokes a model or performs a semantic-neighbour query.
extension _DetailAiPanel on _NoteDetailSheetState {
  Future<void> _readMedia() async {
    final note = _note;
    if (note == null || _readingMedia) return;
    _rebuild(() {
      _readingMedia = true;
      _hideAiResults = false;
      _showAi = true;
      _activeAiResult = note.isImageMedia ? 'image' : 'transcript';
    });
    String? result;
    try {
      result = await widget.services.readMediaOnDemand(note.id);
      await _reload();
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.readMedia', error));
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
      _hideAiResults = false;
      _showAi = true;
      _activeAiResult =
          'attachment-${attachment.id}-${audio ? 'transcript' : 'image'}';
    });
    var success = false;
    try {
      success = await widget.services.readAttachmentOnDemand(attachment.id);
      await _reload();
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.readAttachment', error));
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
    if (_note?.type == NoteType.text || _addingCaption || text.trim().isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    _rebuild(() => _addingCaption = true);
    try {
      final current = await widget.services.getById(widget.noteId);
      if (!mounted || current == null || current.type == NoteType.text) return;
      var choice = _CaptionChoice.append;
      if (current.caption?.trim().isNotEmpty == true) {
        final selected = await nexShowDialog<_CaptionChoice>(
          context: context,
          builder: (dialog) => NexAlertDialog(
            title: NexDialogBody(child: Text(l10n.aiAppendCaptionTitle)),
            scrollable: true,
            content: NexDialogBody(child: Text(l10n.aiAppendCaptionBody)),
            actions: [
              // Three labels cannot reliably share a phone-width action
              // row. Give each choice the full width, including in RTL and
              // with larger text, rather than OverflowBar's trailing stack.
              NexDialogBody(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(dialog, _CaptionChoice.append),
                      child: Text(l10n.aiAppendCaption),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialog, _CaptionChoice.replace),
                      child: Text(l10n.aiReplaceCaption),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text(l10n.cancel),
                    ),
                  ],
                ),
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
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.caption', error));
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
      _hideAiResults = false;
      _showAi = true;
      _activeAiResult = 'summary';
    });
    Summary? summary;
    try {
      summary = await widget.services.summarizeOnDemand(noteId);
      await _reload();
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.summarize', error));
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

  /// "Analyze video" on a YouTube link (2.1.7). Shares the summary's busy
  /// state and its result slot: what comes back is kept as the summary.
  Future<void> _analyzeVideo(String noteId) async {
    if (_summarizing) return;
    _rebuild(() {
      _summarizing = true;
      _hideAiResults = false;
      _showAi = true;
      _activeAiResult = 'summary';
    });
    NexVideoAnalysis analysis;
    try {
      analysis = await widget.services.analyzeVideo(noteId);
      await _reload();
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.analyzeVideo', error));
      analysis = const NexVideoAnalysis.failed(NexVideoFailure.unavailable);
    } finally {
      if (mounted) _rebuild(() => _summarizing = false);
    }
    final failure = analysis.failure;
    if (!mounted || failure == null) return;
    final l10n = AppLocalizations.of(context);
    // Said as what happened (2.1.9): one sentence for every failure sent
    // people looking for a private video when the plan's limit was reached.
    final detail = analysis.detail?.trim() ?? '';
    nexShowBanner(
      context,
      message: switch (failure) {
        NexVideoFailure.limit => l10n.aiVideoFailedLimit,
        NexVideoFailure.slow => l10n.aiVideoFailedSlow,
        NexVideoFailure.refused => l10n.aiVideoFailedRefused(
          nexDigits(
            '${analysis.status ?? ''}',
            persian: l10n.localeName == 'fa',
          ),
          detail.isEmpty
              ? l10n.aiVideoRefusedReason
              : detail.length > 160
              ? '${detail.substring(0, 160)}…'
              : detail,
        ),
        NexVideoFailure.silent => l10n.aiVideoFailedSilent,
        NexVideoFailure.changed => l10n.aiVideoFailedChanged,
        NexVideoFailure.unavailable => l10n.aiVideoFailed,
      },
      kind: NexBannerKind.failed,
      haptics: widget.preferences?.haptics ?? true,
    );
  }

  Future<void> _loadTagSuggestions() async {
    if (_loadingAi) return;
    _rebuild(() {
      _loadingAi = true;
      _hideAiResults = false;
    });
    try {
      final suggestions = await widget.services.suggestTags(widget.noteId);
      if (!mounted) return;
      _rebuild(() => _suggestions = suggestions);
      // Said, not left blank: a tap that ends with nothing on screen reads
      // as a button that does not work. The service answers an empty list
      // for "nothing new to suggest" and for a request that failed alike.
      if (suggestions.isEmpty) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).aiNoTagSuggestions,
          haptics: false,
        );
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.tags', error));
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).aiNoTagSuggestions,
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
      _hideAiResults = false;
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
    if (widget.services.canAnalyzeVideo(note))
      _DetailAction(
        icon: Icons.smart_display_outlined,
        label: l10n.aiAnalyzeVideo,
        accent: true,
        onPressed: _summarizing
            ? null
            : () => unawaited(_analyzeVideo(note.id)),
      ),
    // Not beside "Analyze video": a YouTube page's text is its title and a
    // line of description, and a summary of that is not a summary of the
    // video.
    if (widget.preferences case final preferences?
        when preferences.effectiveAiCapabilities.summarization &&
            aiTextAvailableWith(preferences.aiProvider) &&
            !widget.services.canAnalyzeVideo(note) &&
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
    if (widget.preferences?.effectiveAiCapabilities.tagSuggestions == true &&
        widget.services.aiIsUsable)
      _DetailAction(
        icon: Icons.label_outline,
        label: l10n.aiTagsAction,
        accent: true,
        onPressed: _loadingAi ? null : () => unawaited(_loadTagSuggestions()),
      ),
  ];

  String _translationSource(Note note) =>
      note.isImageMedia ? note.ocrText?.trim() ?? '' : _translatableText(note);

  List<_AiResult> _derivedAiResults(Note note, AppLocalizations l10n) => [
    if (note.transcriptText?.trim().isNotEmpty == true)
      _AiResult('transcript', l10n.transcript, note.transcriptText!.trim()),
    if (note.ocrText?.trim().isNotEmpty == true &&
        !(note.type == NoteType.file &&
            NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType) ==
                NexFileKind.markdown))
      // Markdown source is the document itself, not an AI result.
      // Its presence alone does not mean an image was described by AI.
      _AiResult(
        note.isImageMedia ? 'image' : 'extracted',
        note.isImageMedia ? l10n.aiImageResult : l10n.aiExtractedText,
        note.ocrText!.trim(),
      ),
    if (_summaryIsMeaningful(note))
      _AiResult('summary', l10n.summary, note.summaryText!.trim()),
    for (var i = 0; i < _attachments.length; i++) ...[
      if (_attachments[i].ocrText?.trim().isNotEmpty == true)
        _AiResult(
          'attachment-${_attachments[i].id}-image',
          '${_attachmentReadLabel(_attachments[i], l10n)} · ${nexDigits('${i + 1}', persian: l10n.localeName == 'fa')}',
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

  String _attachmentReadLabel(
    NoteAttachment attachment,
    AppLocalizations l10n,
  ) {
    final image =
        attachment.kind == AttachmentKind.photo ||
        NexFileKinds.of(
              path: attachment.mediaUri,
              mimeType: attachment.mimeType,
            ) ==
            NexFileKind.image;
    return image ? l10n.aiImageResult : l10n.aiExtractedText;
  }

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
    final hasResults =
        derived.isNotEmpty || _translationRequested || _suggestions.isNotEmpty;
    if (!hasResults && actions.isEmpty && !busy) {
      return const SizedBox.shrink();
    }
    final translating =
        _translationRequested && _activeAiResult == 'translation';
    final selected =
        derived.where((r) => r.id == _activeAiResult).firstOrNull ??
        derived.lastOrNull;
    final choices = [
      ...derived,
      if (_translationRequested) _AiResult('translation', l10n.translate, ''),
    ];
    final selectedId = translating ? 'translation' : selected?.id;
    final resultLabel = translating
        ? l10n.translate
        : selected?.label ?? l10n.tagSuggestions;
    final canCaption = note.type != NoteType.text;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.md),
      child: NexAnimatedSize(
        child: NexSurface(
          key: const ValueKey('note-ai-workspace'),
          // A faint wash of the accent and a hairline (2.1.6). It was
          // `surfaceContainerLow`, which every theme makes the same colour as
          // the sheet it sits on, so the workspace's inset read as the AI
          // block being indented further than the note above it for no
          // reason.
          color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.05),
            scheme.surfaceContainerLow,
          ),
          border: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
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
                  if (busy || (hasResults && !translating)) ...[
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: Text(
                        busy ? l10n.aiProcessing : l10n.aiResultReady,
                        key: const ValueKey('note-ai-status'),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  key: const ValueKey('note-ai-tools'),
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  children: [
                    for (final action in actions) _AiActionIcon(action: action),
                  ],
                ),
              ],
              if (busy) ...[
                const SizedBox(height: NexSpacing.sm),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (hasResults) ...[
                const SizedBox(height: NexSpacing.sm),
                if (_hideAiResults)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('note-ai-show-results'),
                      onPressed: () => _rebuild(() => _hideAiResults = false),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(l10n.aiShowResults),
                    ),
                  ),
                // Keep an already-requested translation alive while hiding it.
                // Revealing output or switching results must not call AI again.
                NexReveal(
                  visible: !_hideAiResults,
                  maintainState: true,
                  child: Padding(
                    key: const ValueKey('note-ai-results'),
                    padding: const EdgeInsets.only(top: NexSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: choices.length > 1
                                  ? _AiResultTabs(
                                      choices: choices,
                                      selected: selectedId,
                                      onSelected: (id) =>
                                          _rebuild(() => _activeAiResult = id),
                                    )
                                  : Tooltip(
                                      message: resultLabel,
                                      child: Text(
                                        !translating && selected != null
                                            ? _AiResultTabs.label(
                                                selected,
                                                l10n,
                                              )
                                            : resultLabel,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                            ),
                            if (!translating && selected != null)
                              IconButton(
                                tooltip: _showAi
                                    ? l10n.aiResultCollapse
                                    : l10n.aiResultExpand,
                                onPressed: () =>
                                    _rebuild(() => _showAi = !_showAi),
                                icon: AnimatedRotation(
                                  turns: _showAi ? 0.5 : 0,
                                  duration: NexMotion.of(
                                    context,
                                    NexMotion.standard,
                                  ),
                                  curve: NexMotion.curve,
                                  child: const Icon(
                                    Icons.expand_more,
                                    size: 20,
                                  ),
                                ),
                              ),
                            IconButton(
                              key: const ValueKey('note-ai-hide-results'),
                              tooltip: l10n.hide,
                              onPressed: () =>
                                  _rebuild(() => _hideAiResults = true),
                              icon: const Icon(
                                Icons.visibility_off_outlined,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        if (!translating && selected != null) ...[
                          const SizedBox(height: NexSpacing.xs),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NexSpacing.sm,
                            ),
                            child: _showAi
                                ? ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    child: SingleChildScrollView(
                                      key: ValueKey('ai-result-${selected.id}'),
                                      primary: false,
                                      child: NexTextSurface(
                                        selected.text,
                                        selectable: true,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(height: 1.65),
                                      ),
                                    ),
                                  )
                                : NexTextSurface(
                                    selected.text,
                                    maxLines: 3,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.65,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: NexSpacing.xs),
                          Wrap(
                            spacing: NexSpacing.xs,
                            runSpacing: NexSpacing.xs,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    unawaited(_copyDerivedText(selected.text)),
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                label: Text(l10n.copy),
                              ),
                              if (canCaption)
                                TextButton.icon(
                                  key: ValueKey(
                                    'add-derived-caption-${selected.id}',
                                  ),
                                  onPressed: _addingCaption
                                      ? null
                                      : () => unawaited(
                                          _addDerivedToCaption(selected.text),
                                        ),
                                  icon: const Icon(
                                    Icons.playlist_add_outlined,
                                    size: 18,
                                  ),
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
                              noteId: note.id,
                              embedded: true,
                              addingCaption: _addingCaption,
                              onAddToCaption: canCaption
                                  ? (text) =>
                                        unawaited(_addDerivedToCaption(text))
                                  : null,
                            ),
                          ),
                        if (_suggestions.isNotEmpty) ...[
                          if (selected != null || _translationRequested)
                            Padding(
                              padding: const EdgeInsets.all(NexSpacing.sm),
                              child: Text(
                                l10n.tagSuggestions,
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
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
                                          .where(
                                            (s) => s.name != suggestion.name,
                                          )
                                          .toList(),
                                    );
                                    await _reload();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
            ],
          ),
        ),
      ),
    );
  }

  bool _summaryIsMeaningful(Note note) {
    final summary = note.summaryText?.trim();
    if (summary == null || summary.isEmpty) return false;
    final source = (note.aiSourceText ?? '').trim();
    if (source.isEmpty) return true;
    // A YouTube link's words are its title and a line, so a video analysis
    // is always longer than them and the "shorter than its source" rule hid
    // every one: it worked, was kept, and nothing appeared (2.1.10).
    if (nexYouTubeWatchUrl(note.linkUrl) != null) return summary != source;
    return summary != source && summary.length < source.length;
  }
}
