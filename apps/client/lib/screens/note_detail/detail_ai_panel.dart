part of '../note_detail_sheet.dart';

/// The sheet's AI panel: the summary, related notes and threads.
extension _DetailAiPanel on _NoteDetailSheetState {
  Future<void> _readMedia() async {
    final note = _note;
    if (note == null || _readingMedia) return;
    _rebuild(() {
      _readingMedia = true;
      _showAi = true;
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
    _rebuild(() {
      _readingAttachments.add(attachment.id);
      _showAi = true;
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
      if (current.caption?.trim().isNotEmpty == true) {
        final append = await nexShowDialog<bool>(
          context: context,
          builder: (dialog) => NexAlertDialog(
            title: Text(l10n.aiAppendCaptionTitle),
            content: NexDialogBody(child: Text(l10n.aiAppendCaptionBody)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(l10n.aiAppendCaption),
              ),
            ],
          ),
        );
        if (append != true || !mounted) return;
      }
      final saved = await widget.services.appendCaption(widget.noteId, text);
      await _reload();
      if (mounted) {
        nexShowBanner(
          context,
          message: saved ? l10n.aiCaptionAdded : l10n.aiCaptionFailed,
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

  /// Asks for a summary and says what came back.
  ///
  /// The old version was `await summarizeOnDemand(id); await _reload();` — it
  /// discarded the result and reloaded either way, so a summary that could
  /// not be produced looked exactly like one that had not arrived yet, which
  /// looked exactly like a tap that had not registered.
  Future<void> _summarize(String noteId) async {
    _rebuild(() {
      _summarizing = true;
      _showAi = true;
    });
    Summary? summary;
    try {
      summary = await widget.services.summarizeOnDemand(noteId);
    } finally {
      if (mounted) _rebuild(() => _summarizing = false);
    }
    await _reload();
    if (!mounted || summary != null) return;
    // Gated above on the capability and the provider, so reaching here means
    // the request was made and came back with nothing — a refusal, an
    // unusable answer, or a provider that failed. Which of those it was is
    // not distinguishable here; that it did not work is.
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).summarizeFailed,
      kind: NexBannerKind.failed,
      haptics: widget.preferences?.haptics ?? true,
    );
  }

  /// Opens the intelligence panel, fetching what it needs the first time.
  Future<void> _revealAi() async {
    _rebuild(() {
      _showAi = true;
      _loadingAi = true;
    });
    await _loadAi();
    if (mounted) _rebuild(() => _loadingAi = false);
  }

  Future<void> _loadAi() async {
    final suggestions = await widget.services.suggestTags(widget.noteId);
    final related = await widget.services.relatedNotes(widget.noteId);
    // Resolve the related notes' titles here rather than in build: build runs
    // every frame and each lookup crosses the isolate boundary.
    final titles = <String, String>{};
    for (final hit in related) {
      final note = await widget.services.getById(hit.noteId);
      final content = note?.content;
      if (content != null) titles[hit.noteId] = content;
    }
    if (!mounted) return;
    _rebuild(() {
      _suggestions = suggestions;
      _related = related;
      _relatedTitles = titles;
    });
  }

  /// Everything the intelligence layer produced about this note, behind a tap.
  ///
  /// Media reading is requested through its type-specific action. Opening the
  /// note fetches no model output; a requested result opens this panel directly.
  Widget _aiPanel(Note note, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final derived = <(String, String)>[
      if (note.transcriptText?.trim().isNotEmpty ?? false)
        (l10n.transcript, note.transcriptText!.trim()),
      if (note.ocrText?.trim().isNotEmpty ?? false)
        (l10n.aiImageResult, note.ocrText!.trim()),
      if (_summaryIsMeaningful(note)) (l10n.summary, note.summaryText!.trim()),
      for (var i = 0; i < _attachments.length; i++) ...[
        if (_attachments[i].ocrText?.trim().isNotEmpty == true)
          (
            '${l10n.aiImageResult} · ${nexDigits('${i + 1}', persian: l10n.localeName == 'fa')}',
            _attachments[i].ocrText!.trim(),
          ),
        if (_attachments[i].transcriptText?.trim().isNotEmpty == true)
          (
            '${l10n.transcript} · ${nexDigits('${i + 1}', persian: l10n.localeName == 'fa')}',
            _attachments[i].transcriptText!.trim(),
          ),
      ],
    ];
    // With nothing derived and no provider behind it, the row would promise
    // something the app cannot deliver.
    if (derived.isEmpty && !widget.services.aiIsUsable) {
      return const SizedBox.shrink();
    }

    if (!_showAi) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => unawaited(_revealAi()),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(
            derived.isEmpty
                ? l10n.aiShow
                : l10n.aiReady(derived.map((d) => d.$1).join(' · ')),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.aiSection, style: theme.textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => _rebuild(() => _showAi = false),
              child: Text(l10n.hide),
            ),
          ],
        ),
        for (final (label, body) in derived) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: l10n.copy,
                    color: theme.colorScheme.secondary,
                    icon: const Icon(Icons.copy_outlined, size: 14),
                    onPressed: () => unawaited(_copyDerivedText(body)),
                  ),
                  TextButton.icon(
                    key: ValueKey('add-derived-caption-$label'),
                    style: TextButton.styleFrom(
                      textStyle: theme.textTheme.labelSmall,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _addingCaption
                        ? null
                        : () => unawaited(_addDerivedToCaption(body)),
                    icon: const Icon(Icons.playlist_add_outlined, size: 14),
                    label: Text(l10n.aiAddToCaption),
                  ),
                ],
              ),
            ],
          ),
          // Copy-all is the button above; this is the half of a sentence
          // somebody actually wanted.
          NexTextSurface(body, selectable: true),
          const SizedBox(height: NexSpacing.sm),
        ],
        if (_readingMedia || _readingAttachments.isNotEmpty || _summarizing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: NexSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_loadingAi)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: NexSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_suggestions.isNotEmpty) ...[
          Text(l10n.suggestedTags, style: theme.textTheme.bodySmall),
          Wrap(
            spacing: NexSpacing.xs,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s.name),
                  onPressed: () async {
                    await widget.services.addTag(noteId: note.id, name: s.name);
                    _rebuild(() {
                      _suggestions = _suggestions
                          .where((x) => x.name != s.name)
                          .toList();
                    });
                    _reload();
                  },
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
        if (_related.isNotEmpty) ...[
          Text(l10n.relatedNotes, style: theme.textTheme.bodySmall),
          for (final hit in _related)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _relatedTitles[hit.noteId] ?? hit.noteId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                l10n.similarity(
                  nexDigits(
                    hit.score.toStringAsFixed(2),
                    persian:
                        Localizations.localeOf(context).languageCode == 'fa',
                  ),
                ),
              ),
            ),
        ],
        if (!_loadingAi &&
            !_readingMedia &&
            _readingAttachments.isEmpty &&
            !_summarizing &&
            derived.isEmpty &&
            _suggestions.isEmpty &&
            _related.isEmpty)
          Text(
            l10n.aiNothingYet,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
      ],
    );
  }

  bool _summaryIsMeaningful(Note note) {
    final summary = note.summaryText?.trim();
    if (summary == null || summary.isEmpty) return false;
    final source = (note.aiSourceText ?? '').trim();
    if (source.isEmpty) return summary.isNotEmpty;
    if (summary == source) return false;
    if (summary.length >= source.length) return false;
    return true;
  }
}
