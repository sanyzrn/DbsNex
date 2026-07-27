import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/os_capture_bridge.dart';
import 'package:nex_data/nex_data.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/recording_sheet.dart';
import 'note_detail_sheet.dart';
import 'search_screen.dart';
import 'settings_sheet.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
  });
  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;
  @override
  State<TimelineScreen> createState() => TimelineScreenState();
}

class TimelineScreenState extends State<TimelineScreen> {
  late List<Note> notes = widget.services.search.timeline(limit: 50);
  late final LibraryMaintenance polish = LibraryMaintenance(widget.services.repo);
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (mounted) setState(() => notes = value);
    });
  }

  @override
  void dispose() { subscription?.cancel(); super.dispose(); }

  Future<void> openCapture() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        onCommitted: (id) { landedId = id; if (widget.preferences.haptics) HapticFeedback.lightImpact(); },
        onVoice: () { Navigator.pop(sheetContext); captureVoice(); },
        onCamera: () { Navigator.pop(sheetContext); capturePhoto(ImageSource.camera); },
        onGallery: () { Navigator.pop(sheetContext); capturePhoto(ImageSource.gallery); },
        onFile: () { Navigator.pop(sheetContext); captureFile(); },
      ),
    );
    widget.services.refreshTimeline();
  }

  Future<void> capturePhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final dest = p.join(widget.services.mediaDir,
        'photo-' + DateTime.now().millisecondsSinceEpoch.toString() + p.extension(picked.path));
      await File(dest).writeAsBytes(bytes, flush: true);
      final note = widget.services.capture.submitPhotoCapture(
        mediaUri: dest,
        mediaBytes: Uint8List.fromList(bytes),
      );
      landedId = note.id;
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      widget.services.refreshTimeline();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).captureFailed)),
      );
    }
  }

  Future<void> captureVoice() async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return recorder.dispose();
    final elapsed = Stopwatch()..start();
    final path = p.join(widget.services.mediaDir,
      'voice-' + DateTime.now().millisecondsSinceEpoch.toString() + '.m4a');
    await recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    final keep = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => RecordingSheet(recorder: recorder),
    );
    final recorded = await recorder.stop();
    elapsed.stop();
    await recorder.dispose();
    if (keep != true || recorded == null) { final file = File(path); if (file.existsSync()) file.deleteSync(); return; }
    final bytes = await File(recorded).readAsBytes();
    final note = widget.services.capture.submitVoiceCapture(
      mediaUri: recorded,
      mediaBytes: Uint8List.fromList(bytes),
      durationMs: elapsed.elapsedMilliseconds,
    );
    landedId = note.id;
    widget.services.scheduleEnrichment(note.id);
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    widget.services.refreshTimeline();
  }

  Future<void> captureFile() async {
    final picked = await OsCaptureBridge.pickFile();
    if (picked == null) return;
    await widget.osCapture?.handle({
      'type': 'shared_file', 'path': picked.path,
      'filename': picked.filename, 'mimeType': picked.mimeType,
    });
  }

  void deleteWithUndo(Note note) {
    final l10n = AppLocalizations.of(context);
    widget.services.repo.softDelete(note.id);
    widget.services.refreshTimeline();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.noteDeleted),
      action: SnackBarAction(label: l10n.undo, onPressed: () {
        widget.services.repo.undelete(note.id); widget.services.refreshTimeline();
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final anniversary = widget.preferences.quietAnniversary ? polish.anniversary(DateTime.now()) : <Note>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(tooltip: l10n.search, icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => SearchScreen(services: widget.services)))),
          IconButton(tooltip: l10n.settings, icon: const Icon(Icons.tune),
            onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
              builder: (_) => SettingsSheet(services: widget.services, preferences: widget.preferences))),
        ],
      ),
      body: notes.isEmpty ? const EmptyTimeline() : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 118),
            itemCount: notes.length + (anniversary.isEmpty ? 0 : 1),
            itemBuilder: (context, index) {
              if (anniversary.isNotEmpty && index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text(l10n.oneYearAgo(anniversary.length), style: Theme.of(context).textTheme.bodySmall),
                );
              }
              final note = notes[index - (anniversary.isEmpty ? 0 : 1)];
              return AnimatedSlide(
                offset: landedId == note.id && !MediaQuery.disableAnimationsOf(context)
                    ? const Offset(0, -0.02) : Offset.zero,
                duration: NexMotion.standard,
                child: NoteCard(
                  note: note,
                  onTap: () async {
                    final result = await showModalBottomSheet<DetailResult>(
                      context: context, isScrollControlled: true, useSafeArea: true,
                      builder: (_) => NoteDetailSheet(services: widget.services, noteId: note.id),
                    );
                    if (result == DetailResult.deleted) deleteWithUndo(note);
                    widget.services.refreshTimeline();
                  },
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: openCapture, tooltip: l10n.capture, child: const Icon(Icons.add, size: 32)),
    );
  }
}