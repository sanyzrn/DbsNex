import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';
import '../utils/nex_bidi.dart';

class CaptureSheet extends StatefulWidget {
  const CaptureSheet({
    super.key,
    required this.services,
    required this.onVoice,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    this.onCommitted,
  });
  final NexServices services;
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

  void changed(String value) {
    setState(() {});
    if (noteId == null && value.isNotEmpty) {
      unawaited(_createFirstDraft(value));
      return;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), flush);
  }

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
    // Item 2 fix: Directionality wraps the field, not just the text prop.
    // A TextField whose textDirection disagrees with the ambient
    // Directionality computes its selection painter geometry in the
    // ambient direction and its glyph metrics in the text direction. The
    // symptom is a double-tap in Persian text visually extending to the end
    // of the line even though the copied selection is exactly the word.
    final direction = nexTextDirection(controller.text);
    return PopScope(
      onPopInvokedWithResult: (_, __) => flush(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Directionality(
            textDirection: direction,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: null,
              textDirection: direction,
              textAlign: nexTextAlign(controller.text),
              decoration: InputDecoration(
                  hintText: l10n.captureHint, border: InputBorder.none),
              onChanged: changed,
              onSubmitted: (_) => close(),
            ),
          ),
          const Divider(height: 1),
          Wrap(spacing: 2, children: [
            _Action(Icons.mic_none, l10n.voice, widget.onVoice),
            _Action(Icons.photo_camera_outlined, l10n.camera, widget.onCamera),
            _Action(
                Icons.photo_library_outlined, l10n.gallery, widget.onGallery),
            _Action(Icons.attach_file, l10n.file, widget.onFile),
            IconButton.filled(
              constraints:
                  const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: close,
              tooltip: l10n.capture,
              icon: const Icon(Icons.arrow_upward),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, nexMinTapTarget)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
