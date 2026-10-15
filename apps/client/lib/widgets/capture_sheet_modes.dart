part of 'capture_sheet.dart';

/// The microphone and the field: the two things the box can hold.
extension _CaptureModes on _CaptureSheetState {
  /// The box turns into a recorder and starts listening.
  ///
  /// What was typed stays a note — it already is one — and comes back
  /// unchanged if the recording is discarded.
  Future<void> _startVoice() async {
    if (_voice == _Voice.on || _voiceBusy || _closing) return;
    _voiceBusy = true;
    // The keyboard goes first, while the field still has its focus to give
    // up: a field removed with the focus in it can leave the keyboard up
    // over a recorder that has nothing to type into.
    FocusManager.instance.primaryFocus?.unfocus();
    _set(() => _voice = _Voice.starting);
    final recorder = AudioRecorder();
    NexVoiceSpool? spool;
    try {
      // Say so. A denied microphone used to end the capture on the spot,
      // with no reason — and "nothing" is indistinguishable from a broken
      // control. The banner offers the settings page the permission lives on.
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        if (!mounted) return;
        _set(() => _voice = _Voice.off);
        final l10n = AppLocalizations.of(context);
        nexShowBanner(
          context,
          message: l10n.micDenied,
          actionLabel: l10n.openSettings,
          onAction: () => unawaited(openCaptureSettings()),
          kind: NexBannerKind.failed,
          haptics: widget.preferences.haptics,
        );
        _leaveIfOnlyForVoice();
        return;
      }
      // Straight to an `.m4a`, the way an attached voice clip is (1.99.93);
      // see [NexVoiceSpool.streamNewRecordings] for the spool it replaced.
      spool = await NexVoiceSpool.start(recorder, widget.services.mediaDir);
      // Closed, or discarded, while the microphone was still being asked.
      if (!mounted || _voice != _Voice.starting) {
        await spool.discard();
        await recorder.dispose();
        return;
      }
      _recorder = recorder;
      _spool = spool;
      _recordWatch
        ..reset()
        ..start();
      if (widget.preferences.haptics) {
        unawaited(HapticFeedback.mediumImpact());
      }
      _set(() => _voice = _Voice.on);
    } catch (_) {
      try {
        await spool?.discard();
        await recorder.dispose();
      } catch (_) {}
      if (!mounted) return;
      _set(() => _voice = _Voice.off);
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).captureFailed,
        kind: NexBannerKind.failed,
      );
      _leaveIfOnlyForVoice();
    } finally {
      _voiceBusy = false;
    }
  }

  /// Ends the recording: kept as a voice note, or thrown away.
  Future<void> _stopVoice({required bool keep}) async {
    final recorder = _recorder;
    final spool = _spool;
    _recorder = null;
    _spool = null;
    _recordWatch.stop();
    final ms = _recordWatch.elapsedMilliseconds;
    if (mounted && !_disposed) {
      _set(() => _voice = _Voice.off);
    } else {
      _voice = _Voice.off;
    }
    // Still asking for the microphone: [_startVoice] sees the change and
    // throws away what it opened.
    if (recorder == null || spool == null) return;
    try {
      if (keep) {
        final path = await spool.stop();
        if (path != null) widget.onKeepVoice?.call(path, ms);
      } else {
        await spool.discard();
      }
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      await recorder.dispose();
    }
  }

  /// Stop: the recording is kept, and the sheet closes with everything in
  /// it — the same as Send.
  Future<void> _keepRecording() async {
    if (_closing) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.lightImpact());
    await close();
  }

  /// The bin: the recording goes, and the box turns back into the field —
  /// or, when the sheet was opened only to speak into and nothing has been
  /// typed, the sheet goes with it.
  Future<void> _discardRecording() async {
    if (_closing) return;
    await _stopVoice(keep: false);
    _leaveIfOnlyForVoice();
  }

  void _leaveIfOnlyForVoice() {
    if (!mounted) return;
    if (widget.initialKind == CaptureKind.voice && controller.text.isEmpty) {
      unawaited(close());
    }
  }

  /// Paste into the shared editor, replacing its selection or inserting at
  /// its caret. Keep line breaks and spacing in notes and checklists.
  ///
  /// Read only when asked. Android tells the person every time an app reads
  /// the clipboard, and a sheet that did it on opening would be telling
  /// them on every capture.
  Future<void> _paste() async {
    if (_closing) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _closing || _voiceOn) return;
    final pasted = _kind == CaptureKind.link
        ? data?.text?.trim() ?? ''
        : data?.text ?? '';
    if (pasted.isEmpty) return;
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      pasted,
    );
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + pasted.length,
      ),
    );
    changed(text);
    // The native editor owns a child focus node. Re-requesting the parent
    // steals that focus and briefly drops the IME before restoring it.
    if (!_fieldFocus.hasFocus) _fieldFocus.requestFocus();
  }

  /// The one field the three text kinds share — the same widget in the same
  /// place, so switching kind changes its hint and its keyboard and never
  /// takes the focus or the text away.
  Widget _field(BuildContext context, AppLocalizations l10n) {
    final kind = _kind;
    final enterSends = widget.preferences.enterSubmitsCapture;
    final link = kind == CaptureKind.link;
    final action = switch (kind) {
      // A list is lines: Enter starts the next item, whatever the
      // Enter-sends preference says.
      CaptureKind.checklist => TextInputAction.newline,
      CaptureKind.link => TextInputAction.done,
      _ => enterSends ? TextInputAction.send : TextInputAction.newline,
    };
    // Bounded rather than left to grow with `maxLines: null`: a long paste
    // used to push every tool below it straight off the bottom of the sheet,
    // with no scroll view around the whole thing to recover them. A field
    // given a height constraint from its parent scrolls its own overflow
    // internally instead of demanding more space, so capping the height
    // here is the whole fix — the tool row stays put.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.35,
      ),
      child: Focus(
        // A multiline field's own default is to insert a newline on Enter —
        // textInputAction only changes the on-screen keyboard's action
        // button, physical Enter still needs catching here. Shift+Enter is
        // the escape hatch to actually start a new line while this is on.
        onKeyEvent: (node, event) {
          final submits = link || (kind == CaptureKind.note && enterSends);
          if (!submits || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final isEnter =
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;
          if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
            return KeyEventResult.ignored;
          }
          _submit();
          return KeyEventResult.handled;
        },
        // Android's own editor: each paragraph in its own direction, aligned
        // to its own side, with the system's handles — see [NexTextField]
        // for why a note is never a bare `TextField`.
        child: NexTextField(
          controller: controller,
          focusNode: _fieldFocus,
          autofocus: true,
          minLines: 3,
          readOnly: _closing,
          // Bold, italic and the rest, appended to the platform's own
          // Cut/Copy/Paste rather than replacing them — in a note, where
          // they mean something.
          formatting: kind == CaptureKind.note,
          keyboardType: link ? TextInputType.url : TextInputType.multiline,
          textCapitalization: link
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          autocorrect: !link,
          decoration: InputDecoration(
            hintText: switch (kind) {
              CaptureKind.checklist => l10n.checklistHint,
              CaptureKind.link => l10n.linkHint,
              _ => l10n.captureHint,
            },
            border: InputBorder.none,
            // The composer owns the only surface and outline. The theme
            // supplies focused/enabled borders even when `border` is none,
            // including on Android's native editor (applyDefaults).
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          ),
          textInputAction: action,
          onChanged: changed,
          onSubmitted: action == TextInputAction.newline
              ? null
              : (_) => _submit(),
        ),
      ),
    );
  }
}
