import 'dart:async';
import 'dart:io';
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
  List<Note> notes = const [];
  List<Note> anniversary = const [];
  List<Tag> filterTags = const [];
  String? selectedTagId;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (mounted) setState(() => notes = value);
    });
    unawaited(_loadTimeline());
    unawaited(_loadAnniversary());
    unawaited(_loadFilterTags());
  }

  /// The screen used to seed `notes` synchronously from the repository. The
  /// stream alone is not a replacement: it is a broadcast stream, so anything
  /// emitted before initState subscribes is dropped — a refresh that happens
  /// during startup left the timeline empty.
  Future<void> _loadTimeline() async {
    final loaded = await widget.services.timeline(limit: 200);
    if (!mounted) return;
    setState(() => notes = loaded);
  }

  /// FR-4 filter chips. TagFilterRow shipped in packages/ui, complete and
  /// covered by its own test, but nothing ever imported it — the timeline had
  /// no way to filter at all.
  Future<void> _loadFilterTags() async {
    final loaded = await widget.services.listTags();
    if (!mounted) return;
    setState(() => filterTags = loaded);
  }

  Future<void> _selectTag(String? tagId) async {
    setState(() => selectedTagId = tagId);
    final filtered =
        await widget.services.timeline(limit: 200, tagId: tagId);
    if (!mounted) return;
    setState(() => notes = filtered);
  }

  /// "A year ago today", opt-in and quiet by default. Loaded once rather than
  /// on every build: it is a database query, and build runs on every frame.
  Future<void> _loadAnniversary() async {
    if (!widget.preferences.quietAnniversary) return;
    final found = await widget.services.anniversary(DateTime.now());
    if (!mounted) return;
    setState(() => anniversary = found);
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
      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}',
      );
      await File(dest).writeAsBytes(bytes, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        mediaBytes: Uint8List.fromList(bytes),
      );
      landedId = note.id;
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      await widget.services.refreshTimeline();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).captureFailed)),
        );
      }
    }
  }

  Future<void> captureVoice() async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return recorder.dispose();
    final elapsed = Stopwatch()..start();
    final path = p.join(
      widget.services.mediaDir,
      'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
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
    final note = await widget.services.captureVoice(
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

  Future<void> deleteWithUndo(Note note) async {
    final l10n = AppLocalizations.of(context);
    await widget.services.deleteNote(note.id);
    await widget.services.refreshTimeline();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.noteDeleted),
      action: SnackBarAction(label: l10n.undo, onPressed: () async {
        await widget.services.undelete(note.id);
        await widget.services.refreshTimeline();
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
      body: notes.isEmpty && selectedTagId == null
          ? const EmptyTimeline()
          : Column(children: [
              TagFilterRow(
                tags: filterTags,
                selectedTagId: selectedTagId,
                onSelected: (value) => unawaited(_selectTag(value)),
              ),
              Expanded(child: Center(
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
                    if (result == DetailResult.deleted) {
                      await deleteWithUndo(note);
                    }
                    await widget.services.refreshTimeline();
                  },
                ),
              );
            },
          ),
        ),
              )),
            ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: openCapture, tooltip: l10n.capture, child: const Icon(Icons.add, size: 32)),
    );
  }
}