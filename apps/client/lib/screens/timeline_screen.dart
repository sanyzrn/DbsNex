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
  NoteType? selectedType;
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
    _tick();
    setState(() => selectedTagId = tagId);
    await _applyFilters();
  }

  Future<void> _selectType(NoteType? type) async {
    _tick();
    setState(() => selectedType = type);
    await _applyFilters();
  }

  /// The content-type filter, behind the mockup's icon button.
  Future<void> _pickType() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<_TypeChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in <NoteType?>[null, ...NoteType.values])
              ListTile(
                leading: Icon(_typeIcon(type)),
                title: Text(
                  type == null ? l10n.all : l10n.noteType(type.wireName),
                ),
                trailing: selectedType == type ? const Icon(Icons.check) : null,
                selected: selectedType == type,
                // Wrapped, because popping a bare null cannot be told apart
                // from the user dismissing the sheet.
                onTap: () => Navigator.pop(ctx, _TypeChoice(type)),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _selectType(chosen.type);
  }

  static IconData _typeIcon(NoteType? type) => switch (type) {
        null => Icons.all_inclusive,
        NoteType.text => Icons.short_text,
        NoteType.voice => Icons.graphic_eq,
        NoteType.photo => Icons.photo_outlined,
        NoteType.file => Icons.insert_drive_file_outlined,
      };

  void _tick() {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
  }

  /// FR-4.5: the content-type filter layers on top of the tag filter — it is
  /// not a separate mode, so both selections resolve into one query.
  Future<void> _applyFilters() async {
    final filtered = await widget.services.timeline(
      limit: 200,
      tagId: selectedTagId,
    );
    final type = selectedType;
    if (!mounted) return;
    setState(() => notes = type == null
        ? filtered
        : filtered.where((n) => n.type == type).toList());
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

  /// The non-destructive half of ADR-022's fixed action pair.
  Future<void> _addTagTo(Note note) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addTag),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.tagName),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.addAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    await widget.services.addTag(noteId: note.id, name: name);
    await widget.services.refreshTimeline();
    await _loadFilterTags();
  }

  Future<void> deleteWithUndo(Note note) async {
    final l10n = AppLocalizations.of(context);
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    await widget.services.deleteNote(note.id);
    await widget.services.refreshTimeline();
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // Floating, rounded and inset so it reads as part of the surface
        // rather than a system banner pinned to the bottom edge.
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
        duration: const Duration(seconds: 5),
        backgroundColor: theme.colorScheme.inverseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexColors.cardRadius),
        ),
        content: Row(children: [
          Icon(Icons.delete_outline,
              size: 20, color: theme.colorScheme.onInverseSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.noteDeleted,
              style: TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
          ),
        ]),
        action: SnackBarAction(
          label: l10n.undo,
          textColor: theme.colorScheme.inversePrimary,
          onPressed: () async {
            _tick();
            await widget.services.undelete(note.id);
            await widget.services.refreshTimeline();
          },
        ),
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
          IconButton(tooltip: l10n.settings, icon: const Icon(Icons.settings_outlined),
            // useSafeArea keeps the sheet clear of the status bar; without it
            // the title sat flush against the top of the screen.
            onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
              useSafeArea: true, showDragHandle: true,
              builder: (_) => SettingsSheet(services: widget.services, preferences: widget.preferences))),
        ],
      ),
      body: notes.isEmpty && selectedTagId == null
          ? const EmptyTimeline()
          : Column(children: [
              // One filter row, as in the mockup: the icon button leads it and
              // holds the content-type filter, so the timeline keeps a single
              // row of pills rather than stacking a second one under it.
              TagFilterRow(
                tags: filterTags,
                selectedTagId: selectedTagId,
                allLabel: l10n.all,
                leading: _TypeFilterButton(
                  selected: selectedType,
                  onPressed: () => unawaited(_pickType()),
                ),
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
                // ADR-022: exactly two actions, and only which edge triggers
                // which is configurable. SwipeableNoteCard shipped in
                // packages/ui but nothing ever wrapped a card in it, so the
                // gesture did not exist in the app at all.
                child: SwipeableNoteCard(
                  deleteLabel: l10n.delete,
                  addTagLabel: l10n.addTag,
                  haptics: widget.preferences.haptics,
                  resolveAction: ({required bool isLeading}) {
                    final action = isLeading
                        ? widget.preferences.leadingAction
                        : widget.preferences.trailingAction;
                    return action == SwipeAction.delete
                        ? NexSwipeAction.delete
                        : NexSwipeAction.addTag;
                  },
                  onDelete: () => unawaited(deleteWithUndo(note)),
                  onAddTag: () => unawaited(_addTagTo(note)),
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
/// Wraps the picker's answer so "All" survives the trip back through
/// `Navigator.pop`, which cannot distinguish a null result from a dismissal.
class _TypeChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

/// The mockup's leading icon button on the filter row.
///
/// Carries a dot when a content type is filtering, so an active filter is
/// visible without opening the sheet.
class _TypeFilterButton extends StatelessWidget {
  const _TypeFilterButton({required this.selected, required this.onPressed});

  final NoteType? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selected != null;
    return Material(
      color: active ? theme.colorScheme.onSurface : theme.colorScheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? theme.colorScheme.onSurface : theme.colorScheme.outline,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Icon(
            Icons.tune,
            size: 16,
            color: active ? theme.colorScheme.surface : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
