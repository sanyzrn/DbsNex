import 'dart:async';
import 'dart:ui' show BoxWidthStyle;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'reminder_picker.dart';
import 'text_format_menu.dart';

class CaptureSheet extends StatefulWidget {
  const CaptureSheet({
    super.key,
    required this.services,
    required this.preferences,
    required this.onVoice,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onChecklist,
    required this.onLink,
    this.onCommitted,
  });
  final NexServices services;
  final NexPreferences preferences;
  final VoidCallback onVoice;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onChecklist;
  final VoidCallback onLink;
  final ValueChanged<String>? onCommitted;
  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<CaptureSheet> {
  final controller = TextEditingController();
  Timer? debounce;
  String? noteId;
  String persisted = '';

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

  void changed(String value) {
    setState(() {});
    if (noteId == null && value.isNotEmpty) {
      // One first write, not one per keystroke.
      //
      // `noteId` is only set when that write comes back from the isolate, so
      // every character typed while it was still in flight saw a null id and
      // started another `captureText` — and each of those inserts a note of
      // its own, with no dedup anywhere behind it. Typing "hello" faster than
      // the round trip left "h", "he", "hel" and "hell" in the library for
      // good: only the last id is kept here, so the others could never be
      // flushed to, updated, or deleted by this sheet again. It also called
      // `onCommitted` once per draft, flashing the timeline receipt on notes
      // that were about to be abandoned.
      //
      // The window is not as narrow as an isolate hop sounds. The worker runs
      // one command at a time, so the first capture queues behind whatever is
      // already in flight — a timeline read after a resume, an enrichment
      // call — and an IME that delivers a whole word at once (or a paste)
      // needs no speed at all to get two keystrokes inside it.
      //
      // Nothing is scheduled for the keystrokes this skips: there is no id to
      // flush to yet, and [_createFirstDraft] writes whatever has been typed
      // by the time it lands.
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
    try {
      final note = await widget.services.captureText(value);
      if (note == null) return;
      created = true;
      noteId = note.id;
      persisted = value;
      widget.onCommitted?.call(note.id);

      // Everything typed while this write was in flight. [changed] returned
      // early for those keystrokes rather than scheduling a debounce — there
      // was no id to flush to — so without this the note would keep whatever
      // the first keystroke said and the rest of the word would be lost the
      // moment the user stopped typing.
      if (mounted && controller.text != persisted) flush();
    } finally {
      // Released whenever this settles without producing a note — a capture
      // that returned null, or one that threw. [changed] reads it as "a first
      // write is in flight", and a failure that never released it would leave
      // the sheet unable to save anything for the rest of its life.
      if (!created) draft = null;
    }
  }

  void flush() {
    final id = noteId;
    if (id == null) return;
    if (controller.text.isEmpty) {
      unawaited(widget.services.deleteNote(id));
      noteId = null;
      // And the draft that produced it. [changed] takes a null id with a
      // non-null draft to mean "the first write has not come back yet", so
      // leaving this set would make the sheet refuse to start the next note
      // after someone cleared the field.
      draft = null;
      // The note the reminder was on has just been deleted along with the
      // text. Whatever this sheet is used for next is a different note.
      hasReminder = false;
    } else if (controller.text != persisted) {
      unawaited(widget.services.updateNote(id, controller.text));
      persisted = controller.text;
    }
  }

  /// Sets a reminder on the note being typed, without interrupting the typing.
  ///
  /// The capture sheet has one hard rule over it: nothing may become a
  /// decision on the way in (`docs/07-contributing.md`). A date picker is the
  /// most expensive decision there is, so this button is not on the sheet
  /// until there is something to remind anyone about — an empty sheet is
  /// exactly what it always was — and it never blocks the capture: the note
  /// is already saved by the time the button exists, so this hangs a time on
  /// a note that exists rather than gating one that does not.
  ///
  /// It sits beside the send button rather than in the row of six, because
  /// that row answers "what kind of thing am I capturing" and this answers
  /// "what should happen to it" — the same question the send button answers.
  Future<void> _remind() async {
    await draft;
    // What has been typed since the first keystroke, so a reminder set here
    // is on the note as it now reads. `updateContent` never touches `due_at`
    // and `setDueAt` never touches the content, so the order of these two
    // writes does not matter.
    flush();
    final id = noteId;
    if (id == null) return;
    final note = await widget.services.getById(id);
    if (note == null) return;
    if (!mounted) return;
    await nexPickReminder(
      context: context,
      services: widget.services,
      note: note,
    );
    final saved = await widget.services.getById(id);
    if (!mounted) return;
    setState(() => hasReminder = saved?.dueAt != null);
  }

  void close() {
    flush();
    widget.services.refreshTimeline();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    flush();
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      onPopInvokedWithResult: (_, __) => flush(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bounded rather than left to grow with `maxLines: null`: a long
            // paste used to push the divider and every action icon below it
            // straight off the bottom of the sheet, with no scroll view
            // around the whole thing to recover them. A `TextField` given a
            // height constraint from its parent scrolls its own overflow
            // internally instead of demanding more space, so capping the
            // height here is the whole fix — the icon row stays put.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: Focus(
                // A multiline field's own default is to insert a newline on
                // Enter — textInputAction only changes the on-screen
                // keyboard's action button, physical Enter still needs
                // catching here. Shift+Enter is the escape hatch to actually
                // start a new line while this is on.
                onKeyEvent: (node, event) {
                  if (!widget.preferences.enterSubmitsCapture) {
                    return KeyEventResult.ignored;
                  }
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final isEnter =
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter;
                  if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
                    return KeyEventResult.ignored;
                  }
                  close();
                  return KeyEventResult.handled;
                },
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: null,
                  // Null while the field is empty, which leaves the ambient
                  // direction in place — that is what puts the placeholder at
                  // the right edge in Persian instead of the left. Once there
                  // is text it follows the script being typed, so `start` is
                  // the correct end in either language.
                  textDirection: nexDirectionOf(controller.text),
                  textAlign: TextAlign.start,
                  // Default is BoxWidthStyle.max, which pads a selection's highlight
                  // out to the far edge of its line on Persian text — double-tapping
                  // a word painted a bar running to the end of the line, empty space
                  // included, even though the selection itself (and copy) was always
                  // just the word.
                  selectionWidthStyle: BoxWidthStyle.tight,
                  // Bold, italic and the rest, appended to the platform's own
                  // Cut/Copy/Paste rather than replacing them.
                  contextMenuBuilder: nexFormatContextMenuBuilder(context),
                  decoration: InputDecoration(
                    hintText: l10n.captureHint,
                    border: InputBorder.none,
                  ),
                  textInputAction: widget.preferences.enterSubmitsCapture
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  onChanged: changed,
                  onSubmitted: widget.preferences.enterSubmitsCapture
                      ? (_) => close()
                      : null,
                ),
              ),
            ),
            const Divider(height: 1),
            Wrap(
              spacing: 2,
              children: [
                _Action(Icons.mic_none, l10n.voice, widget.onVoice),
                _Action(
                  Icons.photo_camera_outlined,
                  l10n.camera,
                  widget.onCamera,
                ),
                _Action(
                  Icons.photo_library_outlined,
                  l10n.gallery,
                  widget.onGallery,
                ),
                _Action(Icons.attach_file, l10n.file, widget.onFile),
                _Action(
                  Icons.checklist_rtl_outlined,
                  l10n.checklist,
                  widget.onChecklist,
                ),
                _Action(Icons.link_outlined, l10n.link, widget.onLink),
                // Beside the send button, not among the six: those six change
                // what is being captured, and this changes what happens to it
                // afterwards — the same question the send button answers, so
                // the two sit together and are styled as a pair.
                //
                // It does nudge the send button along on the first keystroke.
                // That is the cost of not having it there on an empty sheet,
                // and the empty sheet is the one that must stay untouched.
                if (controller.text.isNotEmpty)
                  IconButton.filledTonal(
                    constraints: const BoxConstraints.tightFor(
                      width: nexMinTapTarget,
                      height: nexMinTapTarget,
                    ),
                    onPressed: () => unawaited(_remind()),
                    tooltip: l10n.remind,
                    icon: Icon(
                      hasReminder ? Icons.alarm_on : Icons.alarm_add_outlined,
                    ),
                  ),
                IconButton.filled(
                  // The app-wide 48px tap floor. 44 read as a deliberate
                  // exception on the single most-pressed control in the app;
                  // nothing about the filled style needs the smaller box.
                  constraints: const BoxConstraints.tightFor(
                    width: nexMinTapTarget,
                    height: nexMinTapTarget,
                  ),
                  onPressed: close,
                  tooltip: l10n.capture,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon-only on purpose: four of these plus the submit button already read
/// clearly by shape (a mic, a camera, ...), and the label under each one was
/// the only text-heavy thing in a row that is otherwise pure affordance. The
/// name survives as a tooltip and a semantic label — it just stops being
/// printed on the button.
class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    constraints: const BoxConstraints.tightFor(
      width: nexMinTapTarget,
      height: nexMinTapTarget,
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 20),
  );
}
