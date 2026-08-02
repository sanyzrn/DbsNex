import 'dart:async';
import 'dart:ui' show BoxWidthStyle;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../utils/nex_bidi.dart';

class CaptureSheet extends StatefulWidget {
  const CaptureSheet({
    super.key,
    required this.services,
    required this.preferences,
    required this.onVoice,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    this.onCommitted,
  });
  final NexServices services;
  final NexPreferences preferences;
  final VoidCallback onVoice;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final ValueChanged<String>? onCommitted;
  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<CaptureSheet> {
  final controller = TextEditingController();
  Timer? debounce;
  String? noteId;
  String persisted = '';

  /// The clipboard's text, read once when the sheet opens. A capture app's
  /// most common neighbour is whatever the user just copied elsewhere; one
  /// tap drops it into the note. Null (or empty) means no chip.
  String? _clipboard;

  @override
  void initState() {
    super.initState();
    unawaited(_readClipboard());
  }

  Future<void> _readClipboard() async {
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      // No clipboard on this platform, or the OS refused — the chip simply
      // never appears.
      return;
    }
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() => _clipboard = text);
  }

  /// Drops the clipboard into the field the same way typing would: the note
  /// is created by [changed] exactly as if the first keystroke had arrived.
  void _paste() {
    final text = _clipboard;
    if (text == null || text.isEmpty) return;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    controller.text = controller.text.replaceRange(start, end, text);
    controller.selection = TextSelection.collapsed(
      offset: start + text.length,
    );
    setState(() => _clipboard = null);
    changed(controller.text);
  }

  void changed(String value) {
    setState(() {});
    if (noteId == null && value.isNotEmpty) {
      unawaited(_createFirstDraft(value));
      return;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), flush);
  }

  /// The first keystroke persists the note (ADR-002: no Save button). The write
  /// crosses the isolate boundary, so it cannot be awaited on the keystroke
  /// path without dropping frames.
  Future<void> _createFirstDraft(String value) async {
    final note = await widget.services.captureText(value);
    noteId = note?.id;
    persisted = value;
    if (noteId != null) widget.onCommitted?.call(noteId!);
  }

  void flush() {
    final id = noteId;
    if (id == null) return;
    if (controller.text.isEmpty) {
      unawaited(widget.services.deleteNote(id));
      noteId = null;
    } else if (controller.text != persisted) {
      unawaited(widget.services.updateNote(id, controller.text));
      persisted = controller.text;
    }
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
            if (_clipboard != null) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.content_paste, size: 16),
                  label: Text(l10n.paste),
                  tooltip: l10n.pasteClipboard,
                  onPressed: _paste,
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
            ],
            Focus(
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
                textDirection: nexTextDirection(controller.text),
                textAlign: nexTextAlign(controller.text),
                // Default is BoxWidthStyle.max, which pads a selection's highlight
                // out to the far edge of its line on Persian text — double-tapping
                // a word painted a bar running to the end of the line, empty space
                // included, even though the selection itself (and copy) was always
                // just the word.
                selectionWidthStyle: BoxWidthStyle.tight,
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
                IconButton.filled(
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
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
