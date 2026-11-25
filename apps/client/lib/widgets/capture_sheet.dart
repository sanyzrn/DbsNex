import '../platform/crash_reporter.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_core/nex_core.dart'
    show
        NexCodeLanguage,
        NexCodeSnippet,
        Note,
        newUuidV7,
        normaliseUrl,
        parseChecklist,
        urlHost,
        writtenLink;
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
import '../platform/capture_failure.dart' show openCaptureSettings;
import '../platform/display_date.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/voice_spool.dart';
import 'code_editing_controller.dart';
import 'code_input.dart';
import 'code_language_button.dart';
import 'nex_banner.dart';
import 'recording_sheet.dart' show NexLiveWaveform, NexRecordingDot;
import 'reminder_picker.dart';
import 'schedule_picker.dart';
import 'nex_text_field.dart';
import 'keyboard_dismisser.dart';

part 'capture_sheet_writes.dart';

part 'capture_sheet_code.dart';
part 'capture_sheet_modes.dart';
part 'capture_sheet_parts.dart';
part 'capture_sheet_settle.dart';

/// What the capture sheet is making.
enum CaptureKind { note, code, checklist, voice, link }

/// A unified capture sheet for text, checklist, voice and link entries.
/// Edits are journaled as the user types so switching kinds or closing
/// the sheet does not discard unfinished words (ADR-002).
class CaptureSheet extends StatefulWidget {
  const CaptureSheet({
    super.key,
    required this.services,
    required this.preferences,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    this.initialKind = CaptureKind.note,
    this.onCommitted,
    this.onRetracted,
    this.onKeepVoice,
    this.onLinkCaptured,
  });
  final NexServices services;
  final NexPreferences preferences;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;

  /// The kind the sheet opens on. [CaptureKind.voice] starts recording.
  final CaptureKind initialKind;

  /// A note now exists for what is being written: at the first keystroke,
  /// and again when closing turns the words into a list or a link.
  final ValueChanged<String>? onCommitted;

  /// A note [onCommitted] named is gone again — its words became a list or
  /// a link, which [onCommitted] names next.
  final ValueChanged<String>? onRetracted;

  /// A finished recording at a path, and how long it ran in milliseconds,
  /// to keep as a voice note.
  final void Function(String path, int durationMs)? onKeepVoice;

  /// A link note was made from the words; its page is read afterwards.
  final void Function(String noteId, String url)? onLinkCaptured;

  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

/// Where the microphone is: off, asking for itself, or listening.
enum _Voice { off, starting, on }

class _CaptureSheetState extends State<CaptureSheet>
    with WidgetsBindingObserver {
  final controller = NexCodeEditingController(
    text: '',
    language: NexCodeLanguage.plainText,
  );
  final _fieldFocus = FocusNode();

  Timer? debounce;
  String? noteId;
  String persisted = '';
  String _latestText = '';
  String _draftId = newUuidV7();
  Future<void> _writes = Future.value();

  /// The language a code box will save as, until the person chooses another.
  NexCodeLanguage _codeLanguage = NexCodeLanguage.plainText;
  bool _codeLanguageChosen = false;

  /// The fenced Markdown last written for the current [persisted] words.
  ///
  /// [persisted] stays the raw code the box holds — that is what the person
  /// typed — while the note always holds a fenced block. A language change
  /// is a changed note even when the code did not change, so the write guard
  /// compares this as well.
  String _persistedWire = '';

  bool _allowClose = false;
  bool _closing = false;
  bool _scheduling = false;
  bool _hintCounted = false;

  /// Whether this sheet has already said the journal write failed (see
  /// [changed]): a broken journal is a condition, not an event.
  bool _journalFailureTold = false;

  /// Whether the clipboard holds words at all — asked with
  /// [Clipboard.hasStrings], which touches only the clip's description, so
  /// Android does not announce "Nex pasted from your clipboard" for it.
  bool _clipboardHasText = false;

  /// Whether the one read of a clipboard that matters for a link box found
  /// an address in it. Never set for the other kinds: their Paste accepts
  /// whatever words are there.
  bool _clipboardIsLink = false;

  /// Counts clipboard checks. A check that a kind switch or a resumed app has
  /// made stale must not move the button when its answer lands late.
  int _clipboardCheck = 0;

  /// Set while the clipboard is being read and its words inserted, so a
  /// second tap on Paste cannot land them twice.
  bool pasting = false;

  /// Asked when the sheet opens, when the app comes back to the front, when
  /// the box empties and when a link box is entered — the moments the
  /// clipboard can have changed unseen or the kind's own rule started to
  /// matter. Never on a timer, and the words themselves are read only for a
  /// link box, where "pasteable" means "an address".
  Future<void> _checkClipboard() async {
    final check = ++_clipboardCheck;
    var has = false;
    try {
      has = await Clipboard.hasStrings();
    } catch (_) {
      // A clipboard that cannot be asked is a clipboard with nothing to
      // offer; the button stays Send.
    }
    if (!mounted || check != _clipboardCheck) return;
    var isLink = false;
    if (has && _shown == CaptureKind.link) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = (data?.text ?? '').trim();
        isLink = text.isNotEmpty && normaliseUrl(text) != null;
      } catch (_) {}
      if (!mounted || check != _clipboardCheck) return;
    }
    if (has == _clipboardHasText && isLink == _clipboardIsLink) return;
    setState(() {
      _clipboardHasText = has;
      _clipboardIsLink = isLink;
    });
  }

  /// Whether the primary button is Paste: an empty box, and a clipboard this
  /// kind can take. The link box is the one kind that asks what is in it —
  /// a line of prose is not something a link box can paste.
  bool get _canPaste =>
      !_closing &&
      !_voiceOn &&
      controller.text.trim().isEmpty &&
      _clipboardHasText &&
      (_shown != CaptureKind.link || _clipboardIsLink);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkClipboard());
  }

  /// The sheet's one failure voice: failed colours, the setting's own
  /// haptics (a banner that is the direct result of a gesture never adds a
  /// buzz of its own), and the standard capture message unless a site names
  /// its own.
  void _fail([String? message]) {
    if (!mounted) return;
    NexBannerHost.of(context)?.show(
      message: message ?? AppLocalizations.of(context).captureFailed,
      kind: NexBannerKind.failed,
      haptics: widget.preferences.haptics,
    );
  }

  /// The text kinds: what the words become. The microphone is shown over
  /// them rather than replacing the choice, so discarding a recording comes
  /// back to the list it interrupted.
  late CaptureKind _kind = widget.initialKind == CaptureKind.voice
      ? CaptureKind.note
      : widget.initialKind;

  _Voice _voice = _Voice.off;
  bool _voiceBusy = false;
  AudioRecorder? _recorder;
  NexVoiceSpool? _spool;
  final _recordWatch = Stopwatch();

  bool get _voiceOn => _voice != _Voice.off;

  /// `setState` for the parts of this sheet that live in its other files.
  void _set(VoidCallback change) => setState(change);

  /// What the switcher and the box show.
  CaptureKind get _shown => _voiceOn ? CaptureKind.voice : _kind;

  /// The write the first keystroke starts.
  ///
  /// Kept rather than dropped, because a hand can reach the reminder button
  /// before that write lands: it crosses an isolate boundary, and there is
  /// nothing to hang a reminder on until it comes back with an id.
  Future<void>? draft;

  /// Whether the note being typed already has a reminder on it.
  ///
  /// Read back off the note after the picker closes rather than assumed from
  /// what was tapped: the picker can also be dismissed, denied permission, or
  /// used to remove the reminder that was there.
  bool hasReminder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkClipboard());
    if (widget.initialKind == CaptureKind.voice) {
      // The recorder shows from the first frame, not after the permission
      // round trip: a sheet opened to speak into should never flash a
      // keyboard first.
      _voice = _Voice.starting;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startVoice());
      });
    } else {
      _restoreOlderDraft();
    }
  }

  /// A list or a link left half-written by a version that gave each its own
  /// sheet, when the process died with that sheet open. Those kept their
  /// lines in an editor draft rather than as a note; this brings them back
  /// into the box, in their kind, and lets the ordinary first write keep
  /// them from here.
  void _restoreOlderDraft() {
    final drafts = widget.preferences.editorDrafts;
    if (drafts == null) return;
    for (final (key, kind) in [
      ('checklist-new', CaptureKind.checklist),
      ('link-new', CaptureKind.link),
    ]) {
      final text = drafts.read(key)?['text'];
      if (text is! String || text.trim().isEmpty) continue;
      _kind = kind;
      controller.text = text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          // The journal write is serialized inside the journal; a failure
          // is the backstop's to swallow, not this sheet's.
          unawaited(widget.services.captureJournal.write(_draftId, text));
        } catch (_) {}
        changed(text);
        drafts.clear(key);
      });
      return;
    }
  }

  void changed(String value) {
    // The sheet's build reads the typed text only through its emptiness —
    // the schedule hint, the send affordance, the paste/clear side action —
    // so the only rebuilds worth scheduling are the flips between empty and
    // typed. A rebuild per keystroke re-ran the whole sheet — the kind bar,
    // the composer box's AnimatedContainer → AnimatedSize →
    // AnimatedSwitcher chain, the tools wrap — once per character typed,
    // for nothing that changed.
    final beforeTyped = _latestText.trim().isNotEmpty;
    final beforeAny = _latestText.isNotEmpty;
    _latestText = value;
    try {
      widget.services.captureJournal.writeSoon(_draftId, _wireContent(value));
    } catch (_) {
      // The journal being down is a persistent condition and this fires
      // per keystroke: said once per sheet, not once per letter.
      if (!_journalFailureTold) {
        _journalFailureTold = true;
        _fail();
      }
    }
    if (beforeTyped != value.trim().isNotEmpty ||
        beforeAny != value.isNotEmpty) {
      setState(() {});
    }
    // The box emptied: Paste is on the table again, if the clipboard still
    // holds something. Asked here rather than on every keystroke, and only on
    // the flip — the one moment the primary button can change its mind.
    if (value.trim().isEmpty && beforeTyped) unawaited(_checkClipboard());
    if (noteId == null && value.isNotEmpty) {
      // While the first isolate write is pending, do not start another note:
      // the callback takes the latest text after the first id arrives.
      if (draft != null) return;
      final started = _createFirstDraft(value);
      draft = started;
      unawaited(started);
      return;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), flush);
  }

  /// The first keystroke persists the note (ADR-002: no Save button). The write
  /// crosses the isolate boundary, so it cannot be awaited on the keystroke
  /// path without dropping frames.
  Future<void> _createFirstDraft(String value) async {
    var created = false;
    final wire = _wireContent(value);
    try {
      final note = await widget.services.captureDraft(_draftId, wire);
      if (note == null) return;
      created = true;
      noteId = note.id;
      persisted = value;
      _persistedWire = wire;
      if (mounted) widget.onCommitted?.call(note.id);

      // Everything typed while this write was in flight. [changed] returned
      // early for those keystrokes rather than scheduling a debounce — there
      // was no id to flush to — so without this the note would keep whatever
      // the first keystroke said and the rest of the word would be lost the
      // moment the user stopped typing.
      if (_latestText != persisted || _wireContent(_latestText) != wire) {
        await _flushCurrent();
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('capture.firstWrite', error));
      _fail();
    } finally {
      // Released whenever this settles without producing a note — a capture
      // that returned null, or one that threw. [changed] reads it as "a first
      // write is in flight", and a failure that never released it would leave
      // the sheet unable to save anything for the rest of its life.
      if (!created) draft = null;
    }
  }

  Future<void> flush() async {
    debounce?.cancel();
    await draft;
    // If the first insert failed, closing must try the complete snapshot —
    // of actual words: a whitespace-only snapshot is the empty note (see
    // [_flushCurrent]) and gets no second chance at existing.
    if (noteId == null && _latestText.trim().isNotEmpty) {
      draft = _createFirstDraft(_latestText);
      await draft;
    }
    await _flushCurrent();
    if (_matchesStored) {
      try {
        widget.services.captureJournal.complete(_draftId);
      } catch (_) {}
    }
  }

  Future<void> _flushCurrent() {
    final text = _latestText;
    _writes = _writes.then((_) async {
      final id = noteId;
      if (id == null) return;
      // Whitespace is emptiness with a card attached: the first character
      // that made the note may have been a stray space, and a note whose
      // whole text trims to nothing is the one card in the app that
      // promises nothing. It is deleted exactly as the empty text is.
      if (text.trim().isEmpty) {
        try {
          await widget.services.deleteNote(id);
          noteId = null;
          draft = null;
          persisted = '';
          _persistedWire = '';
          hasReminder = false;
          widget.services.captureJournal.complete(_draftId);
          _draftId = newUuidV7();
          if (_latestText.trim().isNotEmpty) {
            unawaited(
              widget.services.captureJournal.write(
                _draftId,
                _wireContent(_latestText),
              ),
            );
            // Let this serialized deletion finish before inserting the new
            // draft typed while its database request was in flight.
            unawaited(Future<void>(() => flush()));
          }
        } catch (error) {
          unawaited(NexCrashLog.handled('capture.draftSwap', error));
          _fail();
        }
      } else {
        final wire = _wireContent(text);
        if (text != persisted || wire != _persistedWire) {
          await _write(id, text, wire);
        }
      }
    });
    return _writes;
  }

  /// Persist before updating the saved snapshot; failures keep the previous
  /// snapshot available for retry while the editor stays open.
  ///
  /// The raw and stored forms are tracked separately because the language
  /// can change while the code itself stays the same.
  Future<void> _write(String id, String text, String wire) async {
    try {
      // The light path: while the sheet is open, a keystroke flush must not
      // read the note back or re-read the whole timeline window (see
      // [NexServices.updateNoteContent]); the closing sheet refreshes once.
      await widget.services.updateNoteContent(
        id,
        wire,
        hasReminder: hasReminder,
      );
      // The worker runs writes in order, so a later one cannot land before
      // this; a newer flush is simply still on its way.
      persisted = text;
      _persistedWire = wire;
    } on Object {
      _fail();
      // Still open: the next flush retries under the person's eyes. Gone:
      // one immediate retry — the services outlive the sheet.
      if (mounted) return;
      try {
        // The reminder is part of what was written under the person's eyes;
        // the retry after the sheet is gone must carry it too, or a reminder
        // set while the code was being typed is silently lost.
        await widget.services.updateNoteContent(
          id,
          wire,
          hasReminder: hasReminder,
        );
        persisted = text;
        _persistedWire = wire;
      } on Object {
        // Twice in a row, with no screen left to say so on. The note keeps
        // the last text that did land.
      }
    }
  }

  /// A single settlement for every way the sheet can close.
  /// A failed conversion preserves the draft and leaves the sheet open.
  Future<bool>? _settling;
  ({Note note, String text, CaptureKind kind})? _conversion;
  String _conversionKey = newUuidV7();

  Future<bool> _settle() => _settling ??= _settleOnce();

  /// A blank field is saved once its draft is gone. Otherwise both the words
  /// and their stored representation (including a code fence) must match.
  bool get _matchesStored => _latestText.trim().isEmpty
      ? noteId == null
      : persisted == _latestText && _wireContent(_latestText) == _persistedWire;

  Future<void> close() async {
    if (_closing) return;
    setState(() => _closing = true);
    if (_voiceOn) await _stopVoice(keep: true);
    final settled = await _settle();
    if (!mounted) return;
    if (!settled || !_matchesStored) {
      // Kept open over words that are not saved yet, so they can be tried
      // again rather than closed over.
      _settling = null;
      setState(() => _closing = false);
      return;
    }
    setState(() => _allowClose = true);
    nexDismissKeyboard(context);
    if (!mounted) return;
    // The sheet goes before the timeline reloads: the reload is the
    // database's business, not something the author of three words waits
    // on. What a send leaves behind is a ✓ on a closing sheet — not a
    // greyed-out, locked one that reads as something having failed. The
    // sheet stays open only on the failure path above, where the words are
    // still unsaved and still editable.
    Navigator.pop(context);
    await widget.services.refreshTimeline();
  }

  /// Whether the words in a link box will not be an address, so closing will
  /// keep them as the note they already are — the `_settleOnce` path. Send
  /// always goes and its glyph says where the words are going; see
  /// [_pasteSlot] for the rest of the way out of the old dead-end.
  bool get _keepingAsNote {
    if (_shown != CaptureKind.link) return false;
    final text = controller.text.trim();
    return text.isNotEmpty && writtenLink(text) == null;
  }

  void _submit() {
    unawaited(close());
  }

  /// Set as `dispose` begins, while `mounted` still says true: nothing may
  /// rebuild from here.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // The journal first: the database write below may still fail, and the
    // snapshot is what a relaunch recovers from.
    widget.services.captureJournal.flushPending();
    // A sheet taken away mid-recording keeps the recording, as closing it
    // any other way does.
    if (_voiceOn) unawaited(_stopVoice(keep: true));
    final settling = _settle();
    // A sheet swiped or backed away never reaches [close], whose refresh
    // follows its last write; the flushes while it was open no longer
    // refresh the timeline, and the one the timeline does when the sheet
    // goes can run before this last write lands. So the timeline is read
    // once more after it, or its card keeps the words from before.
    if (!_allowClose) {
      unawaited(
        settling
            .then<void>((_) => widget.services.refreshTimeline())
            .catchError((Object _) {}),
      );
    } else {
      unawaited(settling);
    }
    debounce?.cancel();
    controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = _shown;
    final typed = controller.text.trim().isNotEmpty;
    final showScheduleHint =
        shown == CaptureKind.note &&
        typed &&
        (_hintCounted || widget.preferences.scheduleHintDue);
    if (showScheduleHint && !_hintCounted) {
      _hintCounted = true;
      unawaited(widget.preferences.countScheduleHint());
    }
    final tools = !_voiceOn;
    return PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(close());
      },
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.xs,
          NexSpacing.md,
          MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KindBar(
              shown: _kind,
              // Closing no longer dims the chips: the words are settled and
              // the sheet is on its way out — a sheet that greys itself at
              // the moment of success looks like one that failed. Taps are
              // simply ignored ([_select] guards on [_closing]).
              recording: _voiceOn,
              onSelect: _select,
            ),
            const SizedBox(height: NexSpacing.sm),
            _ComposerBox(
              kind: shown,
              child: _voiceOn
                  ? _ComposerRecorder(
                      key: const ValueKey('capture-recorder'),
                      recorder: _voice == _Voice.on ? _recorder : null,
                      watch: _recordWatch,
                      color: nexNoteTypeTint(
                        'voice',
                        Theme.of(context).colorScheme,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('capture-field'),
                      child: TextFieldTapRegion(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (shown == CaptureKind.code) _codeToolbar(),
                            Row(
                              key: const ValueKey('capture-input-row'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // The whole width: the primary button is
                                // the one place Paste lives.
                                Expanded(child: _field(context, l10n)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            _ComposerFootnote(
              kind: shown,
              text: controller.text,
              scheduleHint: showScheduleHint,
            ),
            const SizedBox(height: NexSpacing.xs),
            // Everything below stays fully drawn while closing — the tools
            // keep their colour and the buttons their shape; the pointers are
            // simply ignored, rather than the sheet greying itself out.
            IgnorePointer(
              ignoring: _closing,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: NexSpacing.sm,
                runSpacing: NexSpacing.xs,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Tool(
                        icon: Icons.mic_none,
                        label: l10n.voice,
                        type: 'voice',
                        selected: _voiceOn,
                        onTap: tools ? () => _select(CaptureKind.voice) : null,
                      ),
                      _Tool(
                        icon: Icons.photo_camera_outlined,
                        label: l10n.camera,
                        type: 'photo',
                        onTap: tools
                            ? () => unawaited(_leaveFor(widget.onCamera))
                            : null,
                      ),
                      _Tool(
                        icon: Icons.photo_library_outlined,
                        label: l10n.noteType('media'),
                        type: 'photo',
                        onTap: tools
                            ? () => unawaited(_leaveFor(widget.onGallery))
                            : null,
                      ),
                      _Tool(
                        icon: Icons.insert_drive_file_outlined,
                        label: l10n.file,
                        type: 'file',
                        onTap: tools
                            ? () => unawaited(_leaveFor(widget.onFile))
                            : null,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SideAction(
                        recording: _voiceOn,
                        canRemind: controller.text.isNotEmpty,
                        hasReminder: hasReminder,
                        onRemind: () => unawaited(_remind()),
                        onDiscard: _closing
                            ? null
                            : () => unawaited(_discardRecording()),
                      ),
                      const SizedBox(width: NexSpacing.xs),
                      _SendButton(
                        kind: shown,
                        closing: _closing,
                        keepingAsNote: _keepingAsNote,
                        paste: _canPaste,
                        onPaste: _canPaste ? () => unawaited(_paste()) : null,
                        onSend: switch (shown) {
                          CaptureKind.voice =>
                            _voice == _Voice.on
                                ? () => unawaited(_keepRecording())
                                : null,
                          // Including a link box whose words are not an
                          // address: close settles them into the note
                          // they already are, and says so — see
                          // [_keepingAsNote].
                          _ => () => unawaited(close()),
                        },
                        onSchedule: shown == CaptureKind.note && typed
                            ? () => unawaited(_schedule())
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
