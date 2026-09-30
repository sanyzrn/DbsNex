part of '../ai_chat_sheet.dart';

/// Asking and answering: sending a turn, speaking, lookups, history.
extension _ChatSending on _AiChatSheetState {
  /// Whether the microphone is worth offering at all.
  ///
  /// The transcript comes from the same provider the chat does, and two of the
  /// four providers cannot hear audio. A mic button that always failed would
  /// be worse than no mic button.
  bool get _canSpeak =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      widget.preferences.aiProvider.provider.hearsAudio;

  /// Record a question instead of typing it.
  ///
  /// The transcript lands in the composer rather than being sent: speech
  /// recognition on a free-tier model gets names and Persian word breaks
  /// wrong often enough that sending unseen would mean arguing with the
  /// assistant about a question nobody asked. One extra tap buys the chance
  /// to fix it.
  ///
  /// The clip itself is temporary and deleted either way — this is a question,
  /// not a note, and it has no business in the media directory that backups
  /// and the library read from.
  Future<void> _speak() async {
    if (_sending || _transcribing) return;
    final recorder = AudioRecorder();
    // The same silence as voice capture had, in the same words — see
    // `captureVoice`. Dictation is the only way to ask the assistant without
    // typing, so a mute button here reads as the assistant being broken.
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      if (!mounted) return;
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).micDenied,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
      return;
    }
    final file = File(
      p.join(
        Directory.systemTemp.path,
        'nex-ask-${DateTime.now().millisecondsSinceEpoch}.m4a',
      ),
    );
    await recorder.start(const RecordConfig(), path: file.path);
    if (!mounted) {
      await recorder.stop();
      await recorder.dispose();
      return;
    }
    final keep = await nexShowSheet<bool>(
      context: context,
      dismissible: false,
      builder: (_) => RecordingSheet(recorder: recorder),
    );
    final recorded = await recorder.stop();
    await recorder.dispose();
    if (keep != true || recorded == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    if (mounted) _rebuild(() => _transcribing = true);
    String text = '';
    try {
      final transcript = await _adapter.transcribe(
        AudioRef(mediaUri: recorded, bytes: await File(recorded).readAsBytes()),
      );
      text = transcript?.text.trim() ?? '';
    } catch (_) {
      text = '';
    } finally {
      // Deleted whatever happened, including on the throw: a failed request
      // is the case where a stray recording would otherwise sit in temp with
      // nothing left that knows about it.
      if (file.existsSync()) file.deleteSync();
    }
    if (!mounted) return;
    _rebuild(() => _transcribing = false);
    if (text.isEmpty) {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).chatTranscribeFailed,
        haptics: widget.preferences.haptics,
      );
      return;
    }
    nexBump();
    // Appended, not replaced: someone who typed half a question and then
    // spoke the rest meant both halves.
    final existing = _input.text.trimRight();
    _input.text = existing.isEmpty ? text : '$existing $text';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _send(String text, {bool retry = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);

    _rebuild(() {
      if (!retry) {
        _turns.add(ChatMessage(role: ChatRole.user, content: trimmed));
      }
      _sending = true;
      _failure = null;
      _pending = const [];
      _actionResult = null;
      _searchRounds = 0;
      if (!retry) _input.clear();
    });
    _toBottom();

    await _retrieveFor(trimmed);

    String? reply;
    String? requestError;
    try {
      reply = await _ask();
    } on TimeoutException {
      requestError = l10n.chatTimeout;
    } on SocketException {
      requestError = l10n.chatNetworkError;
    } on http.ClientException {
      requestError = l10n.chatNetworkError;
    } catch (_) {
      reply = null;
    }
    if (!mounted) return;

    _rebuild(() {
      _sending = false;
      if (reply == null || reply.isEmpty) {
        _retryText = trimmed;
        // The runtime's own words when the model is what failed. Telling
        // someone who deliberately has no provider to "check the provider in
        // Settings" sends them to the one screen that is already correct.
        final local = _adapter.localFailure;
        _failure =
            requestError ??
            (local != null
                ? l10n.localModelLoadFailed
                : switch (_adapter.lastFailureStatus) {
                    401 || 403 => l10n.chatAuthError,
                    429 => l10n.chatRateLimited,
                    final status? when status >= 500 => l10n.chatServiceError,
                    _ => l10n.chatFailed,
                  });
        return;
      }
      _retryText = null;
      final actions = parseAssistantActions(reply);
      _pending = [
        for (final action in actions)
          if (!action.isRead) action,
      ];
      // A reply that is only an action block has no prose worth showing —
      // the confirmation card says what it is in the user's own language,
      // and the raw JSON underneath it would be noise. A reply carrying both
      // keeps the words and drops the block.
      final prose = actions.isEmpty ? reply : withoutActionBlock(reply);
      if (prose.isNotEmpty) {
        _turns.add(ChatMessage(role: ChatRole.assistant, content: prose));
      }
      _lookups = [
        for (final action in actions)
          if (action.isRead) action,
      ];
    });
    _persist();
    unawaited(_resolveCitations());
    _toBottom();
    if (_lookups.isNotEmpty) await _runLookups();
  }

  /// Runs the assistant's own searches and hands it the results.
  ///
  /// This is what lets it know about a note that is not in the twenty it was
  /// given: it asks, the app looks, and the exchange continues with the
  /// findings in front of it. The results go in as a user turn because that
  /// is the only role every one of the three wire formats agrees on for
  /// something that is neither the system prompt nor the model's own words.
  Future<void> _runLookups() async {
    final queries = _lookups;
    _lookups = const [];
    if (_searchRounds >= 2 || queries.isEmpty) return;
    _searchRounds++;

    final findings = StringBuffer();
    for (final lookup in queries) {
      final query = lookup.text ?? '';
      List<Note> found;
      try {
        // The same ranked list the search field gives (W2.4): words and
        // meaning together, best first. It used to be keyword matches only,
        // newest first — a different answer from the one the reader gets by
        // typing the same thing.
        final parsed = parseSearchQuery(query);
        found = await widget.services.fusedSearch(
          SearchFilters(query: parsed.text, types: parsed.types),
        );
      } catch (_) {
        found = const [];
      }
      findings.writeln('Results for "$query":');
      if (found.isEmpty) {
        findings.writeln('(nothing found)');
      } else {
        _remember(found.take(10));
        for (final note in found.take(10)) {
          final line = _contextLine(note);
          if (line != null) findings.writeln(line);
        }
      }
    }
    if (!mounted) return;

    _rebuild(() {
      _sending = true;
      _turns.add(
        ChatMessage(role: ChatRole.user, content: findings.toString().trim()),
      );
    });
    String? reply;
    try {
      reply = await _ask();
    } catch (_) {
      reply = null;
    }
    if (!mounted) return;
    _rebuild(() {
      _sending = false;
      if (reply == null || reply.isEmpty) {
        _retryText = _turns.last.content;
        _failure = AppLocalizations.of(context).chatFailed;
        return;
      }
      _retryText = null;
      _failure = null;
      final actions = parseAssistantActions(reply);
      _pending = [
        for (final action in actions)
          if (!action.isRead) action,
      ];
      final prose = actions.isEmpty ? reply : withoutActionBlock(reply);
      if (prose.isNotEmpty) {
        _turns.add(ChatMessage(role: ChatRole.assistant, content: prose));
      }
    });
    _persist();
    unawaited(_resolveCitations());
    _toBottom();
  }

  void _remember(Iterable<Note> notes) {
    for (final note in notes) {
      _notes[note.id.toLowerCase()] = note;
      _given.add(note.id);
    }
  }

  Future<String?> _ask() => NexDisclosureLog.about(
    () => _adapter.chat(List.of(_turns), options: _options),
    notes: _given,
  );

  /// Writes the conversation after every exchange. Fire-and-forget: a thread
  /// that fails to save is not worth interrupting the conversation over.
  void _persist() => unawaited(widget.history.save(_threadId, _turns));

  /// Opens the assistant's own settings over the chat.
  ///
  /// Over rather than instead: unlike history, nothing here replaces the
  /// conversation, so the thread is still underneath and still there when the
  /// panel closes. The sheet rebuilds on the way back because every one of
  /// these settings changes what the next answer will be.
  Future<void> _openSettings() async {
    await AssistantSettingsPanel.show(context, preferences: widget.preferences);
    if (mounted) _rebuild(() {});
  }

  /// Swaps this sheet for a saved conversation, or a fresh one.
  ///
  /// Replaces rather than stacks: two assistant sheets on top of each other
  /// is two conversations both claiming to be the one on screen, and the one
  /// underneath would keep saving itself over the one above.
  Future<void> _openHistory() async {
    final chosen = await ChatHistorySheet.show(
      context,
      history: widget.history,
    );
    if (chosen == null || !mounted) return;
    Navigator.pop(context);
    await AiChatSheet.show(
      context,
      preferences: widget.preferences,
      services: widget.services,
      history: widget.history,
      resume: chosen.thread,
    );
  }

  /// After the frame that added the message, not before it — the list has to
  /// have grown before there is anywhere new to scroll to.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
    });
  }
}
