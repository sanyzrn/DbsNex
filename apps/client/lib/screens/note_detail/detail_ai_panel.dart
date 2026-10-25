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

  /// What Nex AI can do with this note, each as a labelled tool (2.3.3).
  /// A tool whose output is kept names the result it fills, so once there is
  /// one the tool shows it instead of asking again.
  List<_AiTool> _aiTools(Note note, AppLocalizations l10n) => [
    if (note.isImageMedia && widget.services.imageReadingAvailable)
      _AiTool(
        icon: Icons.image_search_outlined,
        label: l10n.aiDescribeImage,
        resultId: 'image',
        running: _readingMedia,
        onRun: () => unawaited(_readMedia()),
      ),
    if (note.isAudioMedia && widget.services.audioTranscriptionAvailable)
      _AiTool(
        icon: Icons.transcribe_outlined,
        label: l10n.aiTranscribeAudio,
        resultId: 'transcript',
        running: _readingMedia,
        onRun: () => unawaited(_readMedia()),
      ),
    if (widget.services.canAnalyzeVideo(note))
      _AiTool(
        icon: Icons.smart_display_outlined,
        label: l10n.aiAnalyzeVideo,
        resultId: 'summary',
        running: _summarizing,
        onRun: () => unawaited(_analyzeVideo(note.id)),
      ),
    // Not beside "Analyze video": a YouTube page's text is its title and a
    // line of description, and a summary of that is not a summary of the
    // video.
    if (widget.preferences case final preferences?
        when preferences.effectiveAiCapabilities.summarization &&
            aiTextAvailableWith(preferences.aiProvider) &&
            !widget.services.canAnalyzeVideo(note) &&
            (note.aiSourceText?.length ?? 0) > 80)
      _AiTool(
        glyph: const NexSummariseIcon(),
        label: l10n.summarize,
        resultId: 'summary',
        running: _summarizing,
        onRun: () => unawaited(_summarize(note.id)),
      ),
    if (widget.preferences case final preferences?
        when TranslateSheet.availableFor(preferences) &&
            _translationSource(note).isNotEmpty)
      _AiTool(
        icon: Icons.translate,
        label: l10n.translate,
        resultId: 'translation',
        onRun: _openTranslation,
      ),
    if (widget.preferences case final preferences?
        when AiChatSheet.availableFor(preferences))
      _AiTool(
        icon: Icons.forum_outlined,
        label: l10n.askAboutNote,
        onRun: () => unawaited(
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
      _AiTool(
        icon: Icons.label_outline,
        label: l10n.aiTagsAction,
        running: _loadingAi,
        onRun: () => unawaited(_loadTagSuggestions()),
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

  /// The Nex AI workspace under a note (rebuilt in 2.3.3).
  ///
  /// One header — the name, whether something is working, and Hide/Show for
  /// what came back. One row of labelled tools, which double as the switch
  /// between results: a tool with a result wears a check and shows it, and a
  /// result with no tool of its own (an attachment read, a file's text) joins
  /// the row as a chip. Then the chosen result in a card of its own, with
  /// what can be done with it, and tag suggestions under their own heading.
  Widget _aiPanel(Note note, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final derived = _derivedAiResults(note, l10n);
    final tools = _aiTools(note, l10n);
    final busy =
        _readingMedia ||
        _readingAttachments.isNotEmpty ||
        _summarizing ||
        _loadingAi;
    // A translation made earlier this session comes back with the note, as
    // a result of its own, without asking for it again.
    final translationSource = _translationRequested
        ? _translationText
        : _translationSource(note);
    final hasTranslation =
        _translationRequested ||
        (widget.preferences != null &&
            translationSource.isNotEmpty &&
            TranslateSheet.hasTranslation(translationSource));
    final resultIds = {
      for (final result in derived) result.id,
      if (hasTranslation) 'translation',
    };
    final hasResults = resultIds.isNotEmpty || _suggestions.isNotEmpty;
    if (!hasResults && tools.isEmpty && !busy) return const SizedBox.shrink();
    final selectedId = resultIds.contains(_activeAiResult)
        ? _activeAiResult
        : derived.lastOrNull?.id ?? (hasTranslation ? 'translation' : null);
    final selected = derived.where((r) => r.id == selectedId).firstOrNull;
    final translating = selectedId == 'translation';
    final toolResults = {for (final tool in tools) ?tool.resultId};
    final loose = [
      for (final result in derived)
        if (!toolResults.contains(result.id)) result,
    ];
    void show(String id) => _rebuild(() {
      _activeAiResult = id;
      _hideAiResults = false;
    });
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.md),
      child: NexAnimatedSize(
        child: NexSurface(
          key: const ValueKey('note-ai-workspace'),
          color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.05),
            scheme.surfaceContainerLow,
          ),
          border: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.sm,
            NexSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Flexible(
                      child: Text(
                        l10n.aiSection,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (busy) ...[
                      const SizedBox(width: NexSpacing.sm),
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          key: const ValueKey('note-ai-status'),
                          strokeWidth: 2,
                          semanticsLabel: l10n.aiProcessing,
                        ),
                      ),
                    ],
                    const SizedBox(width: NexSpacing.sm),
                    // Pushed to the far edge, and allowed to shrink: at the
                    // largest text sizes "Show results" shares the line
                    // instead of running off it.
                    if (hasResults)
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _hideAiResults
                              ? TextButton.icon(
                                  key: const ValueKey('note-ai-show-results'),
                                  onPressed: () =>
                                      _rebuild(() => _hideAiResults = false),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l10n.aiShowResults,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : TextButton.icon(
                                  key: const ValueKey('note-ai-hide-results'),
                                  onPressed: () =>
                                      _rebuild(() => _hideAiResults = true),
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l10n.hide,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
                child: Wrap(
                  key: const ValueKey('note-ai-tools'),
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final tool in tools)
                      _AiToolChip(
                        icon: tool.icon,
                        glyph: tool.glyph,
                        label: tool.label,
                        running: tool.running,
                        done: resultIds.contains(tool.resultId),
                        selected:
                            !_hideAiResults &&
                            tool.resultId != null &&
                            tool.resultId == selectedId,
                        onTap: tool.running
                            ? null
                            : resultIds.contains(tool.resultId)
                            ? () => show(tool.resultId!)
                            : tool.onRun,
                      ),
                    for (final result in loose)
                      _AiToolChip(
                        key: ValueKey('note-ai-tab-${result.id}'),
                        icon: _AiResultTabs.icon(result),
                        label: _AiResultTabs.label(result, l10n),
                        tooltip: result.label,
                        done: true,
                        selected: !_hideAiResults && result.id == selectedId,
                        onTap: () => show(result.id),
                      ),
                  ],
                ),
              ),
              if (!hasResults && !busy) ...[
                const SizedBox(height: NexSpacing.md),
                Text(
                  l10n.aiNoResult,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              // Kept alive while hidden: showing it again, or switching
              // between results, never asks the model a second time.
              if (hasResults)
                NexReveal(
                  visible: !_hideAiResults,
                  maintainState: true,
                  child: Padding(
                    key: const ValueKey('note-ai-results'),
                    padding: const EdgeInsetsDirectional.only(
                      top: NexSpacing.md,
                      end: NexSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selected != null && !translating)
                          _AiResultCard(
                            key: ValueKey('ai-result-${selected.id}'),
                            icon: _AiResultTabs.icon(selected),
                            title: _AiResultTabs.label(selected, l10n),
                            text: selected.text,
                            expanded: _showAi,
                            onExpand: () => _rebuild(() => _showAi = !_showAi),
                            onAgain: _againFor(selected.id, note),
                            onCopy: () =>
                                unawaited(_copyDerivedText(selected.text)),
                            onCaption: note.type == NoteType.text
                                ? null
                                : () => unawaited(
                                    _addDerivedToCaption(selected.text),
                                  ),
                            captionBusy: _addingCaption,
                            captionKey: ValueKey(
                              'add-derived-caption-${selected.id}',
                            ),
                          ),
                        if (widget.preferences case final preferences?
                            when hasTranslation)
                          Visibility(
                            visible: translating,
                            maintainState: true,
                            child: _AiCard(
                              child: TranslateSheet(
                                key: ValueKey(
                                  'note-translation-${note.id}-${translationSource.hashCode}',
                                ),
                                text: translationSource,
                                preferences: preferences,
                                services: widget.services,
                                noteId: note.id,
                                addingCaption: _addingCaption,
                                onAddToCaption: note.type == NoteType.text
                                    ? null
                                    : (text) =>
                                          unawaited(_addDerivedToCaption(text)),
                              ),
                            ),
                          ),
                        if (_suggestions.isNotEmpty) ...[
                          if (selectedId != null)
                            const SizedBox(height: NexSpacing.sm),
                          _AiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.label_outline,
                                      size: 16,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: NexSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        l10n.tagSuggestions,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(color: scheme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: NexSpacing.sm),
                                Wrap(
                                  spacing: NexSpacing.xs,
                                  runSpacing: NexSpacing.xs,
                                  children: [
                                    for (final suggestion in _suggestions)
                                      ActionChip(
                                        avatar: const Icon(Icons.add, size: 16),
                                        label: Text(suggestion.name),
                                        onPressed: () => unawaited(
                                          _acceptSuggestion(note, suggestion),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptSuggestion(Note note, TagSuggestion suggestion) async {
    await widget.services.addTag(noteId: note.id, name: suggestion.name);
    if (!mounted) return;
    _rebuild(
      () => _suggestions = _suggestions
          .where((s) => s.name != suggestion.name)
          .toList(),
    );
    await _reload();
  }

  /// "Run again" for a result a tool here can make afresh; null for one it
  /// cannot (an attachment's reading, a file's own text).
  VoidCallback? _againFor(String id, Note note) {
    final tool = _aiTools(
      note,
      AppLocalizations.of(context),
    ).where((t) => t.resultId == id && id != 'translation').firstOrNull;
    if (tool == null || tool.running) return null;
    return tool.onRun;
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
